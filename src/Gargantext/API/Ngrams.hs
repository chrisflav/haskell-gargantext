{-# OPTIONS_GHC -fno-warn-unused-top-binds #-}
{-|
Module      : Gargantext.API.Ngrams
Description : Server API
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

Ngrams API

-- | TODO
get ngrams filtered by NgramsType
add get 

-}

{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeOperators     #-}
{-# LANGUAGE TypeFamilies      #-}

module Gargantext.API.Ngrams
  ( TableNgramsApi
  , TableNgramsApiGet
  , TableNgramsApiPut

  , getTableNgrams
  , setListNgrams
  --, rmListNgrams TODO fix before exporting
  , putListNgrams
  --, putListNgrams'
  , apiNgramsTableCorpus
  , apiNgramsTableDoc

  , NgramsStatePatch
  , NgramsTablePatch
  , NgramsTableMap

  , NgramsTerm(..)

  , NgramsElement(..)
  , mkNgramsElement

  , RootParent(..)

  , MSet
  , mSetFromList
  , mSetToList

  , Repo(..)
  , r_version
  , r_state
  , r_history
  , NgramsRepo
  , NgramsRepoElement(..)
  , saveRepo
  , initRepo

  , RepoEnv(..)
  , renv_var
  , renv_lock

  , TabType(..)
  , ngramsTypeFromTabType

  , HasRepoVar(..)
  , HasRepoSaver(..)
  , HasRepo(..)
  , RepoCmdM
  , QueryParamR
  , TODO

  -- Internals
  , getNgramsTableMap
  , dumpJsonTableMap
  , tableNgramsPull
  , tableNgramsPut

  , Version
  , Versioned(..)
  , currentVersion
  , listNgramsChangedSince
  )
  where

import Control.Concurrent
import Control.Lens ((.~), view, (^.), (^..), (+~), (%~), (.~), sumOf, at, _Just, Each(..), (%%~), mapped)
import Control.Monad.Reader
import Data.Aeson hiding ((.=))
import qualified Data.Aeson.Text as DAT
import Data.Either (Either(..))
import Data.Foldable
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Map.Strict.Patch as PM
import Data.Maybe (fromMaybe)
import Data.Monoid
import Data.Ord (Down(..))
import Data.Patch.Class (Action(act), Transformable(..), ours)
import qualified Data.Set as S
import qualified Data.Set as Set
import Data.Swagger hiding (version, patch)
import Data.Text (Text, isInfixOf, unpack)
import Data.Text.Lazy.IO as DTL
import Formatting (hprint, int, (%))
import Formatting.Clock (timeSpecs)
import GHC.Generics (Generic)
import Servant hiding (Patch)
import System.Clock (getTime, TimeSpec, Clock(..))
import System.IO (stderr)
import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary (Arbitrary, arbitrary)

import Prelude (error)
import Gargantext.Prelude

import Gargantext.API.Admin.Types (HasSettings)
import Gargantext.API.Ngrams.Types
import Gargantext.Core.Types (ListType(..), NodeId, ListId, DocId, Limit, Offset, HasInvalidError, assertValid)
import Gargantext.Core.Types (TODO)
import Gargantext.Core.Viz.Graph.API (recomputeGraph)
import Gargantext.Core.Viz.Graph.Distances (Distance(Conditional))
import Gargantext.Database.Action.Metrics.NgramsByNode (getOccByNgramsOnlyFast')
import Gargantext.Database.Query.Table.Node.Select
import Gargantext.Database.Query.Table.Ngrams hiding (NgramsType(..), ngrams, ngramsType, ngrams_terms)
import Gargantext.Database.Admin.Config (userMaster)
import Gargantext.Database.Query.Table.Node.Error (HasNodeError)
import Gargantext.Database.Admin.Types.Node (NodeType(..))
import Gargantext.Database.Prelude (HasConnectionPool, HasConfig)
import qualified Gargantext.Database.Query.Table.Ngrams as TableNgrams
import Gargantext.Database.Query.Table.Node (getNode)
import Gargantext.Database.Schema.Node (NodePoly(..))

{-
-- TODO sequences of modifications (Patchs)
type NgramsIdPatch = Patch NgramsId NgramsPatch

ngramsPatch :: Int -> NgramsPatch
ngramsPatch n = NgramsPatch (DM.fromList [(1, StopTerm)]) (Set.fromList [n]) Set.empty

toEdit :: NgramsId -> NgramsPatch -> Edit NgramsId NgramsPatch
toEdit n p = Edit n p
ngramsIdPatch :: Patch NgramsId NgramsPatch
ngramsIdPatch = fromList $ catMaybes $ reverse [ replace (1::NgramsId) (Just $ ngramsPatch 1) Nothing
                                       , replace (1::NgramsId) Nothing (Just $ ngramsPatch 2)
                                       , replace (2::NgramsId) Nothing (Just $ ngramsPatch 2)
                                       ]

-- applyPatchBack :: Patch -> IO Patch
-- isEmptyPatch = Map.all (\x -> Set.isEmpty (add_children x) && Set.isEmpty ... )
-}
------------------------------------------------------------------------
------------------------------------------------------------------------
------------------------------------------------------------------------

{-
-- TODO: Replace.old is ignored which means that if the current list
-- `MapTerm` and that the patch is `Replace CandidateTerm StopTerm` then
-- the list is going to be `StopTerm` while it should keep `MapTerm`.
-- However this should not happen in non conflicting situations.
mkListsUpdate :: NgramsType -> NgramsTablePatch -> [(NgramsTypeId, NgramsTerm, ListTypeId)]
mkListsUpdate nt patches =
  [ (ngramsTypeId nt, ng, listTypeId lt)
  | (ng, patch) <- patches ^.. ntp_ngrams_patches . ifolded . withIndex
  , lt <- patch ^.. patch_list . new
  ]

mkChildrenGroups :: (PatchSet NgramsTerm -> Set NgramsTerm)
                 -> NgramsType
                 -> NgramsTablePatch
                 -> [(NgramsTypeId, NgramsParent, NgramsChild)]
mkChildrenGroups addOrRem nt patches =
  [ (ngramsTypeId nt, parent, child)
  | (parent, patch) <- patches ^.. ntp_ngrams_patches . ifolded . withIndex
  , child <- patch ^.. patch_children . to addOrRem . folded
  ]
-}

ngramsTypeFromTabType :: TabType -> TableNgrams.NgramsType
ngramsTypeFromTabType tabType =
  let lieu = "Garg.API.Ngrams: " :: Text in
    case tabType of
      Sources    -> TableNgrams.Sources
      Authors    -> TableNgrams.Authors
      Institutes -> TableNgrams.Institutes
      Terms      -> TableNgrams.NgramsTerms
      _          -> panic $ lieu <> "No Ngrams for this tab"
      -- TODO: This `panic` would disapear with custom NgramsType.

------------------------------------------------------------------------

saveRepo :: ( MonadReader env m, MonadBase IO m, HasRepoSaver env )
         => m ()
saveRepo = liftBase =<< view repoSaver

listTypeConflictResolution :: ListType -> ListType -> ListType
listTypeConflictResolution _ _ = undefined -- TODO Use Map User ListType

ngramsStatePatchConflictResolution
  :: TableNgrams.NgramsType
  -> NodeId
  -> NgramsTerm
  -> ConflictResolutionNgramsPatch
ngramsStatePatchConflictResolution _ngramsType _nodeId _ngramsTerm
  = (ours, (const ours, ours), (False, False))
                             -- (False, False) mean here that Mod has always priority.
                             -- (True, False) <- would mean priority to the left (same as ours).

  -- undefined {- TODO think this through -}, listTypeConflictResolution)

-- Current state:
--   Insertions are not considered as patches,
--   they do not extend history,
--   they do not bump version.
insertNewOnly :: a -> Maybe b -> a
insertNewOnly m = maybe m (const $ error "insertNewOnly: impossible")
  -- TODO error handling

something :: Monoid a => Maybe a -> a
something Nothing  = mempty
something (Just a) = a

{- unused
-- TODO refactor with putListNgrams
copyListNgrams :: RepoCmdM env err m
               => NodeId -> NodeId -> NgramsType
               -> m ()
copyListNgrams srcListId dstListId ngramsType = do
  var <- view repoVar
  liftBase $ modifyMVar_ var $
    pure . (r_state . at ngramsType %~ (Just . f . something))
  saveRepo
  where
    f :: Map NodeId NgramsTableMap -> Map NodeId NgramsTableMap
    f m = m & at dstListId %~ insertNewOnly (m ^. at srcListId)

-- TODO refactor with putListNgrams
-- The list must be non-empty!
-- The added ngrams must be non-existent!
addListNgrams :: RepoCmdM env err m
              => NodeId -> NgramsType
              -> [NgramsElement] -> m ()
addListNgrams listId ngramsType nes = do
  var <- view repoVar
  liftBase $ modifyMVar_ var $
    pure . (r_state . at ngramsType . _Just . at listId . _Just <>~ m)
  saveRepo
  where
    m = Map.fromList $ (\n -> (n ^. ne_ngrams, n)) <$> nes
-}

-- UNSAFE
rmListNgrams ::  RepoCmdM env err m
              => ListId
              -> TableNgrams.NgramsType
              -> m ()
rmListNgrams l nt = setListNgrams l nt mempty

-- | TODO: incr the Version number
-- && should use patch
-- UNSAFE
setListNgrams ::  RepoCmdM env err m
              => NodeId
              -> TableNgrams.NgramsType
              -> Map NgramsTerm NgramsRepoElement
              -> m ()
setListNgrams listId ngramsType ns = do
  var <- view repoVar
  liftBase $ modifyMVar_ var $
    pure . ( r_state
           . at ngramsType %~
             (Just .
               (at listId .~ ( Just ns))
               . something
             )
           )
  saveRepo

-- NOTE
-- This is no longer part of the API.
-- This function is maintained for its usage in Database.Action.Flow.List.
-- If the given list of ngrams elements contains ngrams already in
-- the repo, they will be ignored.
putListNgrams :: (HasInvalidError err, RepoCmdM env err m)
              => NodeId
              -> TableNgrams.NgramsType
              -> [NgramsElement]
              -> m ()
putListNgrams _ _ [] = pure ()
putListNgrams nodeId ngramsType nes = putListNgrams' nodeId ngramsType m
  where
    m = Map.fromList $ map (\n -> (n ^. ne_ngrams, ngramsElementToRepo n)) nes

putListNgrams' :: (HasInvalidError err, RepoCmdM env err m)
               => NodeId
               -> TableNgrams.NgramsType
               -> Map NgramsTerm NgramsRepoElement
               -> m ()
putListNgrams' nodeId ngramsType ns = do
  -- printDebug "[putListNgrams'] nodeId" nodeId
  -- printDebug "[putListNgrams'] ngramsType" ngramsType
  -- printDebug "[putListNgrams'] ns" ns

  let p1 = NgramsTablePatch . PM.fromMap $ NgramsReplace Nothing . Just <$> ns
      (p0, p0_validity) = PM.singleton nodeId p1
      (p, p_validity) = PM.singleton ngramsType p0
  assertValid p0_validity
  assertValid p_validity
  {-
  -- TODO
  v <- currentVersion
  q <- commitStatePatch (Versioned v p)
  assert empty q
  -- What if another commit comes in between?
  -- Shall we have a blindCommitStatePatch? It would not ask for a version but just a patch.
  -- The modifyMVar_ would test the patch with applicable first.
  -- If valid the rest would be atomic and no merge is required.
  -}
  var <- view repoVar
  liftBase $ modifyMVar_ var $ \r -> do
    pure $ r & r_version +~ 1
             & r_history %~ (p :)
             & r_state . at ngramsType %~
               (Just .
                 (at nodeId %~
                   ( Just
                   . (<> ns)
                   . something
                   )
                 )
                 . something
               )
  saveRepo


currentVersion :: RepoCmdM env err m
               => m Version
currentVersion = do
  var <- view repoVar
  r   <- liftBase $ readMVar var
  pure $ r ^. r_version


-- tableNgramsPut :: (HasInvalidError err, RepoCmdM env err m)
commitStatePatch :: RepoCmdM env err m => Versioned NgramsStatePatch -> m (Versioned NgramsStatePatch)
commitStatePatch (Versioned p_version p) = do
  var <- view repoVar
  vq' <- liftBase $ modifyMVar var $ \r -> do
    let
      q = mconcat $ take (r ^. r_version - p_version) (r ^. r_history)
      (p', q') = transformWith ngramsStatePatchConflictResolution p q
      r' = r & r_version +~ 1
             & r_state   %~ act p'
             & r_history %~ (p' :)
    {-
    -- Ideally we would like to check these properties. However:
    -- * They should be checked only to debug the code. The client data
    --   should be able to trigger these.
    -- * What kind of error should they throw (we are in IO here)?
    -- * Should we keep modifyMVar?
    -- * Should we throw the validation in an Exception, catch it around
    --   modifyMVar and throw it back as an Error?
    assertValid $ transformable p q
    assertValid $ applicable p' (r ^. r_state)
    -}
    pure (r', Versioned (r' ^. r_version) q')

  saveRepo
  pure vq'

-- This is a special case of tableNgramsPut where the input patch is empty.
tableNgramsPull :: RepoCmdM env err m
                => ListId
                -> TableNgrams.NgramsType
                -> Version
                -> m (Versioned NgramsTablePatch)
tableNgramsPull listId ngramsType p_version = do
  var <- view repoVar
  r <- liftBase $ readMVar var

  let
    q = mconcat $ take (r ^. r_version - p_version) (r ^. r_history)
    q_table = q ^. _PatchMap . at ngramsType . _Just . _PatchMap . at listId . _Just

  pure (Versioned (r ^. r_version) q_table)

-- Apply the given patch to the DB and returns the patch to be applied on the
-- client.
-- TODO-ACCESS check
tableNgramsPut :: (HasNodeError err,
                   HasInvalidError err,
                   HasConfig env,
                   HasConnectionPool env,
                   HasSettings env,
                   RepoCmdM env err m)
                 => TabType
                 -> ListId
                 -> Versioned NgramsTablePatch
                 -> m (Versioned NgramsTablePatch)
tableNgramsPut tabType listId (Versioned p_version p_table)
  | p_table == mempty = do
      let ngramsType        = ngramsTypeFromTabType tabType
      tableNgramsPull listId ngramsType p_version

  | otherwise         = do
      let ngramsType        = ngramsTypeFromTabType tabType
          (p0, p0_validity) = PM.singleton listId p_table
          (p, p_validity)   = PM.singleton ngramsType p0

      assertValid p0_validity
      assertValid p_validity

      ret <- commitStatePatch (Versioned p_version p)
        <&> v_data %~ (view (_PatchMap . at ngramsType . _Just . _PatchMap . at listId . _Just))

      node <- getNode listId
      let nId = _node_id node
          uId = _node_userId node
      _ <- recomputeGraph uId nId Conditional

      pure ret
     
  {-
  { _ne_list        :: ListType
  If we merge the parents/children we can potentially create cycles!
  , _ne_parent      :: Maybe NgramsTerm
  , _ne_children    :: MSet NgramsTerm
  }
  -}

getNgramsTableMap :: RepoCmdM env err m
                  => NodeId
                  -> TableNgrams.NgramsType
                  -> m (Versioned NgramsTableMap)
getNgramsTableMap nodeId ngramsType = do
  v    <- view repoVar
  repo <- liftBase $ readMVar v
  pure $ Versioned (repo ^. r_version)
                   (repo ^. r_state . at ngramsType . _Just . at nodeId . _Just)

dumpJsonTableMap :: RepoCmdM env err m
                 => Text
                 -> NodeId
                 -> TableNgrams.NgramsType
                 -> m ()
dumpJsonTableMap fpath nodeId ngramsType = do
  m <- getNgramsTableMap nodeId ngramsType
  liftBase $ DTL.writeFile (unpack fpath) (DAT.encodeToLazyText m)
  pure ()

type MinSize = Int
type MaxSize = Int

-- | TODO Errors management
--  TODO: polymorphic for Annuaire or Corpus or ...
-- | Table of Ngrams is a ListNgrams formatted (sorted and/or cut).
-- TODO: should take only one ListId

getTime' :: MonadBase IO m => m TimeSpec
getTime' = liftBase $ getTime ProcessCPUTime


getTableNgrams :: forall env err m.
                  (RepoCmdM env err m, HasNodeError err, HasConnectionPool env, HasConfig env)
               => NodeType -> NodeId -> TabType
               -> ListId -> Limit -> Maybe Offset
               -> Maybe ListType
               -> Maybe MinSize -> Maybe MaxSize
               -> Maybe OrderBy
               -> (NgramsTerm -> Bool)
               -> m (Versioned NgramsTable)
getTableNgrams _nType nId tabType listId limit_ offset
               listType minSize maxSize orderBy searchQuery = do

  t0 <- getTime'
  -- lIds <- selectNodesWithUsername NodeList userMaster
  let
    ngramsType = ngramsTypeFromTabType tabType
    offset'  = maybe 0 identity offset
    listType' = maybe (const True) (==) listType
    minSize'  = maybe (const True) (<=) minSize
    maxSize'  = maybe (const True) (>=) maxSize

    selected_node n = minSize'     s
                   && maxSize'     s
                   && searchQuery  (n ^. ne_ngrams)
                   && listType'    (n ^. ne_list)
      where
        s = n ^. ne_size

    selected_inner roots n = maybe False (`Set.member` roots) (n ^. ne_root)

    ---------------------------------------
    sortOnOrder Nothing = identity
    sortOnOrder (Just TermAsc)   = List.sortOn $ view ne_ngrams
    sortOnOrder (Just TermDesc)  = List.sortOn $ Down . view ne_ngrams
    sortOnOrder (Just ScoreAsc)  = List.sortOn $ view ne_occurrences
    sortOnOrder (Just ScoreDesc) = List.sortOn $ Down . view ne_occurrences

    ---------------------------------------
    selectAndPaginate :: Map NgramsTerm NgramsElement -> [NgramsElement]
    selectAndPaginate tableMap = roots <> inners
      where
        list = tableMap ^.. each
        rootOf ne = maybe ne (\r -> fromMaybe (panic "getTableNgrams: invalid root") (tableMap ^. at r))
                             (ne ^. ne_root)
        selected_nodes = list & take limit_
                              . drop offset'
                              . filter selected_node
                              . sortOnOrder orderBy
        roots = rootOf <$> selected_nodes
        rootsSet = Set.fromList (_ne_ngrams <$> roots)
        inners = list & filter (selected_inner rootsSet)

    ---------------------------------------
    setScores :: forall t. Each t t NgramsElement NgramsElement => Bool -> t -> m t
    setScores False table = pure table
    setScores True  table = do
      let ngrams_terms = unNgramsTerm <$> (table ^.. each . ne_ngrams)
      t1 <- getTime'
      occurrences <- getOccByNgramsOnlyFast' nId
                                             listId
                                            ngramsType
                                            ngrams_terms
      t2 <- getTime'
      liftBase $ hprint stderr
        ("getTableNgrams/setScores #ngrams=" % int % " time=" % timeSpecs % "\n")
        (length ngrams_terms) t1 t2
      {-
      occurrences <- getOccByNgramsOnlySlow nType nId
                                            (lIds <> [listId])
                                            ngramsType
                                            ngrams_terms
      -}
      let
        setOcc ne = ne & ne_occurrences .~ sumOf (at (unNgramsTerm (ne ^. ne_ngrams)) . _Just) occurrences

      pure $ table & each %~ setOcc
    ---------------------------------------

  -- lists <- catMaybes <$> listsWith userMaster
  -- trace (show lists) $
  -- getNgramsTableMap ({-lists <>-} listIds) ngramsType

  let scoresNeeded = needsScores orderBy
  tableMap1 <- getNgramsTableMap listId ngramsType
  t1 <- getTime'
  tableMap2 <- tableMap1 & v_data %%~ setScores scoresNeeded
                                    . Map.mapWithKey ngramsElementFromRepo
  t2 <- getTime'
  tableMap3 <- tableMap2 & v_data %%~ fmap NgramsTable
                                    . setScores (not scoresNeeded)
                                    . selectAndPaginate
  t3 <- getTime'
  liftBase $ hprint stderr
            ("getTableNgrams total=" % timeSpecs
                          % " map1=" % timeSpecs
                          % " map2=" % timeSpecs
                          % " map3=" % timeSpecs
                          % " sql="  % (if scoresNeeded then "map2" else "map3")
                          % "\n"
            ) t0 t3 t0 t1 t1 t2 t2 t3
  pure tableMap3


scoresRecomputeTableNgrams :: forall env err m. (RepoCmdM env err m, HasNodeError err, HasConnectionPool env, HasConfig env) => NodeId -> TabType -> ListId -> m Int
scoresRecomputeTableNgrams nId tabType listId = do
  tableMap <- getNgramsTableMap listId ngramsType
  _ <- tableMap & v_data %%~ setScores
                           . Map.mapWithKey ngramsElementFromRepo

  pure $ 1
  where
    ngramsType = ngramsTypeFromTabType tabType

    setScores :: forall t. Each t t NgramsElement NgramsElement => t -> m t
    setScores table = do
      let ngrams_terms = unNgramsTerm <$> (table ^.. each . ne_ngrams)
      occurrences <- getOccByNgramsOnlyFast' nId
                                             listId
                                            ngramsType
                                            ngrams_terms
      let
        setOcc ne = ne & ne_occurrences .~ sumOf (at (unNgramsTerm (ne ^. ne_ngrams)) . _Just) occurrences

      pure $ table & each %~ setOcc



-- APIs

-- TODO: find a better place for the code above, All APIs stay here

data OrderBy = TermAsc | TermDesc | ScoreAsc | ScoreDesc
             deriving (Generic, Enum, Bounded, Read, Show)

instance FromHttpApiData OrderBy
  where
    parseUrlPiece "TermAsc"   = pure TermAsc
    parseUrlPiece "TermDesc"  = pure TermDesc
    parseUrlPiece "ScoreAsc"  = pure ScoreAsc
    parseUrlPiece "ScoreDesc" = pure ScoreDesc
    parseUrlPiece _           = Left "Unexpected value of OrderBy"


instance ToParamSchema OrderBy
instance FromJSON  OrderBy
instance ToJSON    OrderBy
instance ToSchema  OrderBy
instance Arbitrary OrderBy
  where
    arbitrary = elements [minBound..maxBound]

needsScores :: Maybe OrderBy -> Bool
needsScores (Just ScoreAsc)  = True
needsScores (Just ScoreDesc) = True
needsScores _ = False

type TableNgramsApiGet = Summary " Table Ngrams API Get"
                      :> QueryParamR "ngramsType"  TabType
                      :> QueryParamR "list"        ListId
                      :> QueryParamR "limit"       Limit
                      :> QueryParam  "offset"      Offset
                      :> QueryParam  "listType"    ListType
                      :> QueryParam  "minTermSize" MinSize
                      :> QueryParam  "maxTermSize" MaxSize
                      :> QueryParam  "orderBy"     OrderBy
                      :> QueryParam  "search"      Text
                      :> Get    '[JSON] (Versioned NgramsTable)

type TableNgramsApiPut = Summary " Table Ngrams API Change"
                       :> QueryParamR "ngramsType" TabType
                       :> QueryParamR "list"       ListId
                       :> ReqBody '[JSON] (Versioned NgramsTablePatch)
                       :> Put     '[JSON] (Versioned NgramsTablePatch)

type RecomputeScoresNgramsApiGet = Summary " Recompute scores for ngrams table"
                       :> QueryParamR "ngramsType"  TabType
                       :> QueryParamR "list"        ListId
                       :> "recompute" :> Post '[JSON] Int

type TableNgramsApiGetVersion = Summary " Table Ngrams API Get Version"
                      :> QueryParamR "ngramsType"  TabType
                      :> QueryParamR "list"        ListId
                      :> Get    '[JSON] Version

type TableNgramsApi =  TableNgramsApiGet
                  :<|> TableNgramsApiPut
                  :<|> RecomputeScoresNgramsApiGet
                  :<|> "version" :> TableNgramsApiGetVersion

getTableNgramsCorpus :: (RepoCmdM env err m, HasNodeError err, HasConnectionPool env, HasConfig env)
               => NodeId
               -> TabType
               -> ListId
               -> Limit
               -> Maybe Offset
               -> Maybe ListType
               -> Maybe MinSize -> Maybe MaxSize
               -> Maybe OrderBy
               -> Maybe Text -- full text search
               -> m (Versioned NgramsTable)
getTableNgramsCorpus nId tabType listId limit_ offset listType minSize maxSize orderBy mt =
  getTableNgrams NodeCorpus nId tabType listId limit_ offset listType minSize maxSize orderBy searchQuery
    where
      searchQuery (NgramsTerm nt) = maybe (const True) isInfixOf mt nt

getTableNgramsVersion :: (RepoCmdM env err m, HasNodeError err, HasConnectionPool env, HasConfig env)
               => NodeId
               -> TabType
               -> ListId
               -> m Version
getTableNgramsVersion _nId _tabType _listId = currentVersion
  -- TODO: limit?
  -- Versioned { _v_version = v } <- getTableNgramsCorpus nId tabType listId 100000 Nothing Nothing Nothing Nothing Nothing Nothing
  -- This line above looks like a waste of computation to finally get only the version.
  -- See the comment about listNgramsChangedSince.


-- | Text search is deactivated for now for ngrams by doc only
getTableNgramsDoc :: (RepoCmdM env err m, HasNodeError err, HasConnectionPool env, HasConfig env)
               => DocId -> TabType
               -> ListId -> Limit -> Maybe Offset
               -> Maybe ListType
               -> Maybe MinSize -> Maybe MaxSize
               -> Maybe OrderBy
               -> Maybe Text -- full text search
               -> m (Versioned NgramsTable)
getTableNgramsDoc dId tabType listId limit_ offset listType minSize maxSize orderBy _mt = do
  ns <- selectNodesWithUsername NodeList userMaster
  let ngramsType = ngramsTypeFromTabType tabType
  ngs <- selectNgramsByDoc (ns <> [listId]) dId ngramsType
  let searchQuery (NgramsTerm nt) = flip S.member (S.fromList ngs) nt
  getTableNgrams NodeDocument dId tabType listId limit_ offset listType minSize maxSize orderBy searchQuery



apiNgramsTableCorpus :: ( RepoCmdM env err m
                        , HasNodeError err
                        , HasInvalidError err
                        , HasConnectionPool env
                        , HasConfig         env
                        , HasSettings       env
                        )
                     => NodeId -> ServerT TableNgramsApi m
apiNgramsTableCorpus cId =  getTableNgramsCorpus cId
                       :<|> tableNgramsPut
                       :<|> scoresRecomputeTableNgrams cId
                       :<|> getTableNgramsVersion cId

apiNgramsTableDoc :: ( RepoCmdM env err m
                     , HasNodeError err
                     , HasInvalidError err
                     , HasConnectionPool env
                     , HasConfig         env
                     , HasSettings       env
                     )
                  => DocId -> ServerT TableNgramsApi m
apiNgramsTableDoc dId =  getTableNgramsDoc dId
                    :<|> tableNgramsPut
                    :<|> scoresRecomputeTableNgrams dId
                    :<|> getTableNgramsVersion dId
                    -- > index all the corpus accordingly (TODO AD)

-- Did the given list of ngrams changed since the given version?
-- The returned value is versioned boolean value, meaning that one always retrieve the
-- latest version.
-- If the given version is negative then one simply receive the latest version and True.
-- Using this function is more precise than simply comparing the latest version number
-- with the local version number. Indeed there might be no change to this particular list
-- and still the version number has changed because of other lists.
--
-- Here the added value is to make a compromise between precision, computation, and bandwidth:
-- * currentVersion: good computation, good bandwidth, bad precision.
-- * listNgramsChangedSince: good precision, good bandwidth, bad computation.
-- * tableNgramsPull: good precision, good bandwidth (if you use the received data!), bad computation.
listNgramsChangedSince :: RepoCmdM env err m
                       => ListId -> TableNgrams.NgramsType -> Version -> m (Versioned Bool)
listNgramsChangedSince listId ngramsType version
  | version < 0 =
      Versioned <$> currentVersion <*> pure True
  | otherwise   =
      tableNgramsPull listId ngramsType version & mapped . v_data %~ (== mempty)
