{-|
Module      : Gargantext.Database.Query.Facet
Description : Main requests of Node to the database
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX
-}

{-# OPTIONS_GHC -fno-warn-orphans      #-}

{-# LANGUAGE Arrows                    #-}
{-# LANGUAGE FunctionalDependencies    #-}
{-# LANGUAGE QuasiQuotes               #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TypeFamilies              #-}
------------------------------------------------------------------------
module Gargantext.Database.Query.Facet
  ( runViewAuthorsDoc
  , runViewDocuments
--   , viewDocuments'
  , runCountDocuments
  , filterWith

  , Category
  , Score
  , Title

  , Pair(..)
  , Facet(..)
  , FacetDoc
  , FacetDocRead
  , FacetPaired(..)
  , FacetPairedRead
  , FacetPairedReadNull
  , FacetPairedReadNullAgg
  , OrderBy(..)
  )
  where

import Control.Arrow (returnA, (>>>))
import Control.Lens ((^.))
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson.TH (deriveJSON)
--import qualified Database.PostgreSQL.Simple as DPS
--import Database.PostgreSQL.Simple.SqlQQ (sql)
import Data.Profunctor.Product.TH (makeAdaptorAndInstance)
import Data.Swagger
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.Time.Segment (jour)
import Opaleye
import Protolude hiding (null, map, sum, not)
import Servant.API
import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary
import qualified Opaleye.Internal.Unpackspec()

import Gargantext.Core
import Gargantext.Core.Types
import Gargantext.Core.Utils.Prefix (unPrefix, unPrefixSwagger, wellNamedSchema)
-- import Gargantext.Database.Action.TSQuery (toTSQuery)
import Gargantext.Database.Admin.Types.Hyperdata
import Gargantext.Database.Query.Filter
import Gargantext.Database.Query.Join (leftJoin5)
import Gargantext.Database.Query.Table.Ngrams
import Gargantext.Database.Query.Table.Context
import Gargantext.Database.Schema.Context
import Gargantext.Database.Query.Table.NodeContext
import Gargantext.Database.Query.Table.ContextNodeNgrams
import Gargantext.Database.Prelude
import Gargantext.Database.Schema.Node
import Gargantext.Prelude (printDebug)

------------------------------------------------------------------------
-- | DocFacet

-- data Facet = FacetDoc | FacetSources | FacetAuthors | FacetTerms
--    deriving (Show, Generic)
--instance FromJSON Facet
--instance ToJSON   Facet

type Category = Int
type Score    = Double
type Title    = Text

-- TODO remove Title
type FacetDoc = Facet NodeId UTCTime Title HyperdataDocument (Maybe Category) (Maybe Double) (Maybe Score)
-- type FacetSources = FacetDoc
-- type FacetAuthors = FacetDoc
-- type FacetTerms   = FacetDoc


data Facet id created title hyperdata category ngramCount score =
     FacetDoc { facetDoc_id         :: id
              , facetDoc_created    :: created
              , facetDoc_title      :: title
              , facetDoc_hyperdata  :: hyperdata
              , facetDoc_category   :: category
              , facetDoc_ngramCount :: ngramCount
              , facetDoc_score      :: score
              } deriving (Show, Generic)
{- | TODO after demo
data Facet id date hyperdata score =
     FacetDoc { facetDoc_id        :: id
              , facetDoc_date      :: date
              , facetDoc_hyperdata :: hyperdata
              , facetDoc_score     :: score
              } deriving (Show, Generic)
-}

data Pair i l = Pair {
    _p_id    :: i
  , _p_label :: l
  } deriving (Show, Generic)
$(deriveJSON (unPrefix "_p_") ''Pair)
$(makeAdaptorAndInstance "pPair" ''Pair)

instance (Typeable i, Typeable l, ToSchema i, ToSchema l) => ToSchema (Pair i l) where
  declareNamedSchema = wellNamedSchema "_p_"
instance (Arbitrary i, Arbitrary l) => Arbitrary (Pair i l) where
  arbitrary = Pair <$> arbitrary <*> arbitrary

data FacetPaired id date hyperdata score =
  FacetPaired { _fp_id        :: id
              , _fp_date      :: date
              , _fp_hyperdata :: hyperdata
              , _fp_score     :: score }
  deriving (Show, Generic)
$(deriveJSON (unPrefix "_fp_") ''FacetPaired)
$(makeAdaptorAndInstance "pFacetPaired" ''FacetPaired)



instance ( ToSchema id
         , ToSchema date
         , ToSchema hyperdata
         , ToSchema score
         , Typeable id
         , Typeable date
         , Typeable hyperdata
         , Typeable score
         ) => ToSchema (FacetPaired id date hyperdata score) where
  declareNamedSchema = wellNamedSchema "_fp_"

instance ( Arbitrary id
         , Arbitrary date
         , Arbitrary hyperdata
         , Arbitrary score
         ) => Arbitrary (FacetPaired id date hyperdata score) where
  arbitrary = FacetPaired <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

type FacetPairedRead = FacetPaired (Column SqlInt4       )
                                   (Column SqlTimestamptz)
                                   (Column SqlJsonb      )
                                   (Column SqlInt4       )

type FacetPairedReadNull = FacetPaired (Column (Nullable SqlInt4)       )
                                       (Column (Nullable SqlTimestamptz))
                                       (Column (Nullable SqlJsonb)      )
                                       (Column (Nullable SqlInt4)       )

type FacetPairedReadNullAgg = FacetPaired (Aggregator (Column (Nullable SqlInt4)       )
                                                      (Column (Nullable SqlInt4)       )
                                          )
                                          (Aggregator (Column (Nullable SqlTimestamptz))
                                                      (Column (Nullable SqlTimestamptz))

                                          )
                                          (Aggregator (Column (Nullable SqlJsonb)      )
                                                      (Column (Nullable SqlJsonb)      )
                                          )
                                          (Aggregator (Column (Nullable SqlInt4)       )
                                                      (Column (Nullable SqlInt4)       )
                                          )




-- | JSON instance
$(deriveJSON (unPrefix "facetDoc_") ''Facet)

-- | Documentation instance
instance ToSchema FacetDoc where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "facetDoc_")

-- | Mock and Quickcheck instances
instance Arbitrary FacetDoc where
    arbitrary = elements [ FacetDoc id' (jour year 01 01) t hp (Just cat) (Just ngramCount) (Just score)
                         | id'        <- [1..10]
                         , year       <- [1990..2000]
                         , t          <- ["title", "another title"]
                         , hp         <- arbitraryHyperdataDocuments
                         , cat        <- [0..2]
                         , ngramCount <- [3..100]
                         , score      <- [3..100]
                         ]

-- Facets / Views for the Front End
-- | Database instances
$(makeAdaptorAndInstance "pFacetDoc" ''Facet)
-- $(makeLensesWith abbreviatedFields   ''Facet)

type FacetDocRead = Facet (Column SqlInt4       )
                          (Column SqlTimestamptz)
                          (Column SqlText       )
                          (Column SqlJsonb      )
                          (Column (Nullable SqlInt4)) -- Category
                          (Column (Nullable SqlFloat8)) -- Ngrams Count
                          (Column (Nullable SqlFloat8)) -- Score

-----------------------------------------------------------------------
-----------------------------------------------------------------------
data OrderBy =  DateAsc   | DateDesc
             | TitleAsc   | TitleDesc
             | ScoreDesc  | ScoreAsc
             | SourceAsc  | SourceDesc
             deriving (Generic, Enum, Bounded, Read, Show)

instance FromHttpApiData OrderBy
  where
    parseUrlPiece "DateAsc"    = pure DateAsc
    parseUrlPiece "DateDesc"   = pure DateDesc
    parseUrlPiece "TitleAsc"   = pure TitleAsc
    parseUrlPiece "TitleDesc"  = pure TitleDesc
    parseUrlPiece "ScoreAsc"   = pure ScoreAsc
    parseUrlPiece "ScoreDesc"  = pure ScoreDesc
    parseUrlPiece "SourceAsc"  = pure SourceAsc
    parseUrlPiece "SourceDesc" = pure SourceDesc
    parseUrlPiece _            = Left "Unexpected value of OrderBy"
instance ToHttpApiData OrderBy where
  toUrlPiece = T.pack . show

instance ToParamSchema OrderBy
instance FromJSON  OrderBy
instance ToJSON    OrderBy
instance ToSchema  OrderBy
instance Arbitrary OrderBy
  where
    arbitrary = elements [minBound..maxBound]


-- TODO-SECURITY check
runViewAuthorsDoc :: HasDBid NodeType
                  => ContactId
                  -> IsTrash
                  -> Maybe Offset
                  -> Maybe Limit
                  -> Maybe OrderBy
                  -> Cmd err [FacetDoc]
runViewAuthorsDoc cId t o l order = runOpaQuery $ filterWith o l order $ viewAuthorsDoc cId t ntId
  where
    ntId = NodeDocument

-- TODO add delete ?
viewAuthorsDoc :: HasDBid NodeType
               => ContactId
               -> IsTrash
               -> NodeType
               -> Select FacetDocRead
viewAuthorsDoc cId _ nt = proc () -> do
  (doc,(_,(_,(_,contact')))) <- queryAuthorsDoc      -< ()

  restrict -< _node_id   contact'  .== (toNullable $ pgNodeId cId)
  restrict -< _node_typename doc   .== (sqlInt4 $ toDBid nt)

  returnA  -< FacetDoc { facetDoc_id         = _node_id        doc
                       , facetDoc_created    = _node_date      doc
                       , facetDoc_title      = _node_name      doc
                       , facetDoc_hyperdata  = _node_hyperdata doc
                       , facetDoc_category   = toNullable $ sqlInt4 1
                       , facetDoc_ngramCount = toNullable $ sqlDouble 1
                       , facetDoc_score      = toNullable $ sqlDouble 1 }

queryAuthorsDoc :: Select (NodeRead, (ContextNodeNgramsReadNull, (NgramsReadNull, (ContextNodeNgramsReadNull, NodeReadNull))))
queryAuthorsDoc = leftJoin5 queryNodeTable queryContextNodeNgramsTable queryNgramsTable queryContextNodeNgramsTable queryNodeTable cond12 cond23 cond34 cond45
    where
         cond12 :: (ContextNodeNgramsRead, NodeRead) -> Column SqlBool
         cond12 (nodeNgram, doc) =  _node_id doc
                                .== _cnng_context_id nodeNgram

         cond23 :: (NgramsRead, (ContextNodeNgramsRead, NodeReadNull)) -> Column SqlBool
         cond23 (ngrams', (nodeNgram, _)) =  ngrams'^.ngrams_id
                                        .== _cnng_ngrams_id nodeNgram

         cond34 :: (ContextNodeNgramsRead, (NgramsRead, (ContextNodeNgramsReadNull, NodeReadNull))) -> Column SqlBool
         cond34 (nodeNgram2, (ngrams', (_,_)))= ngrams'^.ngrams_id .== _cnng_ngrams_id       nodeNgram2

         cond45 :: (NodeRead, (ContextNodeNgramsRead, (NgramsReadNull, (ContextNodeNgramsReadNull, NodeReadNull)))) -> Column SqlBool
         cond45 (contact', (nodeNgram2', (_, (_,_)))) = _node_id  contact'  .== _cnng_context_id         nodeNgram2'


------------------------------------------------------------------------
-- TODO-SECURITY check
runViewDocuments :: HasDBid NodeType
                 => CorpusId
                 -> IsTrash
                 -> Maybe Offset
                 -> Maybe Limit
                 -> Maybe OrderBy
                 -> Maybe Text
                 -> Maybe Text
                 -> Cmd err [FacetDoc]
runViewDocuments cId t o l order query year = do
    printDebug "[runViewDocuments] sqlQuery" $ showSql sqlQuery
    runOpaQuery $ filterWith o l order sqlQuery
  where
    sqlQuery = viewDocuments cId t (toDBid NodeDocument) query year

runCountDocuments :: HasDBid NodeType => CorpusId -> IsTrash -> Maybe Text -> Maybe Text -> Cmd err Int
runCountDocuments cId t mQuery mYear = do
  runCountOpaQuery sqlQuery
  where
    sqlQuery = viewDocuments cId t (toDBid NodeDocument) mQuery mYear


viewDocuments :: CorpusId
              -> IsTrash
              -> NodeTypeId
              -> Maybe Text
              -> Maybe Text
              -> Select FacetDocRead
viewDocuments cId t ntId mQuery mYear = viewDocumentsQuery cId t ntId mQuery mYear >>> proc (c, nc) -> do
  returnA  -< FacetDoc { facetDoc_id         = _cs_id        c
                       , facetDoc_created    = _cs_date      c
                       , facetDoc_title      = _cs_name      c
                       , facetDoc_hyperdata  = _cs_hyperdata c
                       , facetDoc_category   = toNullable $ nc^.nc_category
                       , facetDoc_ngramCount = toNullable $ nc^.nc_score
                       , facetDoc_score      = toNullable $ nc^.nc_score
                       }

viewDocumentsQuery :: CorpusId
                   -> IsTrash
                   -> NodeTypeId
                   -> Maybe Text
                   -> Maybe Text
                   -> Select (ContextSearchRead, NodeContextRead)
viewDocumentsQuery cId t ntId mQuery mYear = proc () -> do
  c  <- queryContextSearchTable -< ()
  nc <- queryNodeContextTable   -< ()
  restrict -< c^.cs_id         .== nc^.nc_context_id
  restrict -< nc^.nc_node_id   .== (pgNodeId cId)
  restrict -< c^.cs_typename   .== (sqlInt4 ntId)
  restrict -< if t then nc^.nc_category .== (sqlInt4 0)
                   else nc^.nc_category .>= (sqlInt4 1)

  let
    query         = (fromMaybe "" mQuery)
    year          = (fromMaybe "" mYear)
    iLikeQuery    = T.intercalate "" ["%", query, "%"]
    abstractLHS h = fromNullable (sqlStrictText "")
                  $ toNullable h .->> (sqlStrictText "abstract")
    yearLHS h     = fromNullable (sqlStrictText "")
                  $ toNullable h .->> (sqlStrictText "publication_year")

  restrict -<
    if query == "" then sqlBool True
      else  ((c^.cs_name) `ilike` (sqlStrictText iLikeQuery))
        .|| ((abstractLHS (c^.cs_hyperdata)) `ilike` (sqlStrictText iLikeQuery))
  restrict -<
    if year == "" then sqlBool True
      else (yearLHS (c^.cs_hyperdata)) .== (sqlStrictText year)

  returnA -< (c, nc)


------------------------------------------------------------------------
filterWith :: (SqlOrd date, SqlOrd title, SqlOrd category, SqlOrd score, hyperdata ~ Column SqlJsonb) =>
        Maybe Gargantext.Core.Types.Offset
     -> Maybe Gargantext.Core.Types.Limit
     -> Maybe OrderBy
     -> Select (Facet id (Column date) (Column title) hyperdata (Column category) ngramCount (Column score))
     -> Select (Facet id (Column date) (Column title) hyperdata (Column category) ngramCount (Column score))
filterWith o l order q = limit' l $ offset' o $ orderBy (orderWith order) q


orderWith :: (SqlOrd b1, SqlOrd b2, SqlOrd b3, SqlOrd b4)
          => Maybe OrderBy
          -> Order (Facet id (Column b1) (Column b2) (Column SqlJsonb) (Column b3) ngramCount (Column b4))
orderWith (Just DateAsc)   = asc  facetDoc_created
orderWith (Just DateDesc)  = desc facetDoc_created

orderWith (Just TitleAsc)  = asc  facetDoc_title
orderWith (Just TitleDesc) = desc facetDoc_title

orderWith (Just ScoreAsc)  = asc  facetDoc_score
orderWith (Just ScoreDesc) = descNullsLast facetDoc_score

orderWith (Just SourceAsc)  = asc  facetDoc_source
orderWith (Just SourceDesc) = desc facetDoc_source

orderWith _                = asc facetDoc_created

facetDoc_source :: SqlIsJson a
                => Facet id created title (Column a) favorite ngramCount score
                -> Column (Nullable SqlText)
facetDoc_source x = toNullable (facetDoc_hyperdata x) .->> sqlString "source"
