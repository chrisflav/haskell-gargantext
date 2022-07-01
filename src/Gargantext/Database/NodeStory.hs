{-# LANGUAGE Arrows #-}
{-# LANGUAGE TemplateHaskell           #-}

module Gargantext.Database.NodeStory where

import Control.Arrow (returnA)
import Control.Concurrent.MVar.Lifted (MVar(), withMVar, newMVar, modifyMVar_)
--import Control.Debounce (mkDebounce, defaultDebounceSettings, debounceFreq, debounceAction)
import Control.Monad (foldM)
import qualified Data.Map.Strict as Map
import Data.Profunctor.Product.TH (makeAdaptorAndInstance)
import Gargantext.API.Ngrams.Tools (getRepo)
import Gargantext.Core (HasDBid)
import Gargantext.Core.Mail.Types (HasMail)
import Gargantext.Core.NodeStory (Archive(..), NodeStory(..), NodeListStory, NgramsState', NgramsStatePatch')
import qualified Gargantext.Core.NodeStory as NS
import Gargantext.Core.Types (NodeId(..), NodeType(..))
import Gargantext.Database.Prelude (Cmd, mkCmd, runOpaQuery)
import Gargantext.Database.Query.Table.Node (getNodesIdWithType, nodeExists)
import Gargantext.Database.Query.Table.Node.Error (HasNodeError)
import Gargantext.Prelude
import Opaleye hiding (FromField)
import Opaleye.Internal.Table (Table(..))


data NodeStoryPoly a b = NodeStoryDB { node_id :: a
                                     , archive :: b }
  deriving (Eq)

type ArchiveQ = Archive NgramsState' NgramsStatePatch'

type NodeListStoryQ = NodeStoryPoly Int ArchiveQ

type NodeStoryWrite = NodeStoryPoly (Column SqlInt4) (Column SqlJsonb)
type NodeStoryRead = NodeStoryPoly (Column SqlInt4) (Column SqlJsonb)

$(makeAdaptorAndInstance "pNodeStory" ''NodeStoryPoly)

nodeStoryTable :: Table NodeStoryRead NodeStoryWrite
nodeStoryTable =
  Table "node_stories"
    ( pNodeStory NodeStoryDB { node_id = tableField "node_id"
                             , archive = tableField "archive" } )
  
nodeStorySelect :: Select NodeStoryRead
nodeStorySelect = selectTable nodeStoryTable

getNodeStory :: NodeId -> Cmd err NodeListStory
getNodeStory (NodeId nodeId) = do
  res <- runOpaQuery query
  pure $ NodeStory $ Map.fromListWith (<>) $ (\(NodeStoryDB nId a) -> (nId, a)) <$> res
  where
    query :: Select NodeStoryRead
    query = proc () -> do
      row@(NodeStoryDB node_id _) <- nodeStorySelect -< ()
      restrict -< node_id .== sqlInt4 nodeId
      returnA -< row

insertNodeArchive :: NodeId -> ArchiveQ -> Cmd err Int64
insertNodeArchive (NodeId nId) a = mkCmd $ \c -> runInsert c insert
  where
    insert = Insert { iTable      = nodeStoryTable
                    , iRows       = [NodeStoryDB { node_id = sqlInt4 nId
                                                 , archive = sqlValueJSONB a }]
                    , iReturning  = rCount
                    , iOnConflict = Nothing }

updateNodeArchive :: NodeId -> ArchiveQ -> Cmd err Int64
updateNodeArchive (NodeId nId) a = mkCmd $ \c -> runUpdate c update
  where
    update = Update { uTable      = nodeStoryTable
                    , uUpdateWith = updateEasy (\(NodeStoryDB { .. }) -> NodeStoryDB { archive = sqlValueJSONB a, .. })
                    , uWhere      = (\row -> node_id row .== sqlInt4 nId)
                    , uReturning  = rCount }

nodeStoryRemove :: NodeId -> Cmd err Int64
nodeStoryRemove (NodeId nId) = mkCmd $ \c -> runDelete c delete
  where
    delete = Delete { dTable     = nodeStoryTable
                    , dWhere     = (\row -> node_id row .== sqlInt4 nId)
                    , dReturning = rCount }

upsertNodeArchive :: NodeId -> ArchiveQ -> Cmd err Int64
upsertNodeArchive nId a = do
  (NodeStory m) <- getNodeStory nId
  case Map.lookup nId m of
    Nothing -> insertNodeArchive nId a
    Just _  -> updateNodeArchive nId a

writeNodeStories :: NodeListStory -> Cmd err ()
writeNodeStories (NodeStory nls) = do
  _ <- mapM (\(nId, a) -> upsertNodeArchive nId a) $ Map.toList nls
  pure ()
  
-- | Returns a `NodeListStory`, updating the given one for given `NodeId`
nodeStoryInc :: Maybe NodeListStory -> NodeId -> Cmd err NodeListStory
nodeStoryInc Nothing nId = getNodeStory nId
nodeStoryInc (Just ns@(NodeStory nls)) nId = do
  case Map.lookup nId nls of
    Nothing -> do
      (NodeStory nls') <- getNodeStory nId
      pure $ NodeStory $ Map.union nls nls'
    Just _ -> pure ns

nodeStoryIncs :: Maybe NodeListStory -> [NodeId] -> Cmd err NodeListStory
nodeStoryIncs Nothing [] = pure $ NodeStory $ Map.empty
nodeStoryIncs (Just nls) ns = foldM (\m n -> nodeStoryInc (Just m) n) nls ns
nodeStoryIncs Nothing (ni:ns) = do
  m <- getNodeStory ni
  nodeStoryIncs (Just m) ns

nodeStoryDec :: NodeListStory -> NodeId -> Cmd err NodeListStory
nodeStoryDec ns@(NodeStory nls) ni = do
  case Map.lookup ni nls of
    Nothing -> do
      _ <- nodeStoryRemove ni
      pure ns
    Just _ -> do
      let ns' = Map.filterWithKey (\k _v -> k /= ni) nls
      _ <- nodeStoryRemove ni
      pure $ NodeStory ns'

migrateFromDir :: (HasMail env, HasNodeError err, NS.HasNodeStory env err m, HasDBid NodeType)
               => m ()
migrateFromDir = do
  listIds <- getNodesIdWithType NodeList
  (NodeStory nls) <- getRepo listIds
  _ <- mapM (\(nId, a) -> do
                n <- nodeExists nId
                case n of
                  False -> pure 0
                  True  -> upsertNodeArchive nId a
            ) $ Map.toList nls
  --_ <- nodeStoryIncs (Just $ NodeStory nls) listIds
  pure ()

------------------------------------

data NodeStoryEnv err = NodeStoryEnv
  { _nse_var    :: !(MVar NodeListStory)
  , _nse_saver  :: !(Cmd err ())
  , _nse_getter :: [NodeId] -> Cmd err (MVar NodeListStory)
  --, _nse_cleaner :: !(IO ()) -- every 12 hours: cleans the repos of unused NodeStories
  -- , _nse_lock  :: !FileLock -- TODO (it depends on the option: if with database or file only)
  }
  --deriving (Generic)


nodeStoryEnv :: Cmd err (NodeStoryEnv err)
nodeStoryEnv = do
  mvar <- nodeStoryVar Nothing []
  --saver <- mkNodeStorySaver mvar
  let saver = mkNodeStorySaver mvar
  -- let saver = modifyMVar_ mvar $ \mv' -> do
  --       writeNodeStories mv'
  --       return mv'
  pure $ NodeStoryEnv { _nse_var    = mvar
                      , _nse_saver  = saver
                      , _nse_getter = nodeStoryVar (Just mvar) }

nodeStoryVar :: Maybe (MVar NodeListStory) -> [NodeId] -> Cmd err (MVar NodeListStory)
nodeStoryVar Nothing nIds = do
  state <- nodeStoryIncs Nothing nIds
  newMVar state
nodeStoryVar (Just mv) nIds = do
  _ <- modifyMVar_ mv $ \nsl -> (nodeStoryIncs (Just nsl) nIds)
  pure mv

-- TODO No debounce since this is IO stuff.
-- debounce is useful since it could delay the saving to some later
-- time, asynchronously and we keep operating on memory only.
mkNodeStorySaver :: MVar NodeListStory -> Cmd err ()
mkNodeStorySaver mvns = withMVar mvns writeNodeStories

-- mkNodeStorySaver :: MVar NodeListStory -> Cmd err (Cmd err ())
-- mkNodeStorySaver mvns = mkDebounce settings
--   where
--     settings = defaultDebounceSettings
--                  { debounceAction = withMVar mvns (\ns -> writeNodeStories ns)
--                  , debounceFreq = 1 * minute
-- --                 , debounceEdge = trailingEdge -- Trigger on the trailing edge
--                  }
--     minute = 60 * second
--     second = 10^(6 :: Int)

