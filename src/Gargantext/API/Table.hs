{-|
Module      : Gargantext.API.Node
Description : Server API
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX


-- TODO-ACCESS: CanGetNode
-- TODO-EVENTS: No events as this is a read only query.
Node API

-------------------------------------------------------------------
-- TODO-ACCESS: access by admin only.
--              At first let's just have an isAdmin check.
--              Later: check userId CanDeleteNodes Nothing
-- TODO-EVENTS: DeletedNodes [NodeId]
--              {"tag": "DeletedNodes", "nodes": [Int*]}


-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeOperators        #-}

module Gargantext.API.Table
  where

import Data.Aeson.TH (deriveJSON)
import Data.Maybe
import Data.Swagger
import Data.Text (Text())
import GHC.Generics (Generic)
import Servant
import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary (Arbitrary, arbitrary)

import Gargantext.API.HashedResponse
import Gargantext.API.Ngrams.Types (TabType(..))
import Gargantext.API.Prelude (GargServer)
import Gargantext.Core.Types (TableResult(..))
import Gargantext.Core.Types.Query (Offset, Limit)
import Gargantext.Core.Utils.Prefix (unPrefix, unPrefixSwagger)
import Gargantext.Database.Action.Learn (FavOrTrash(..), moreLike)
import Gargantext.Database.Action.Search
import Gargantext.Database.Admin.Types.Node
import Gargantext.Database.Query.Table.Node.Error (HasNodeError)
import Gargantext.Database.Query.Facet (FacetDoc , runViewDocuments, runCountDocuments, OrderBy(..), runViewAuthorsDoc)
import Gargantext.Database.Prelude -- (Cmd, CmdM)
import Gargantext.Prelude

------------------------------------------------------------------------

type TableApi = Summary "Table API"
              :> QueryParam "tabType" TabType
              :> QueryParam "limit" Limit
              :> QueryParam "offset" Offset
              :> QueryParam "orderBy" OrderBy
              :> QueryParam "query" Text
              :> QueryParam "year" Text
              :> Get    '[JSON] (HashedResponse FacetTableResult)
            :<|> Summary "Table API (POST)"
              :> ReqBody '[JSON] TableQuery
              :> Post    '[JSON] FacetTableResult
            :<|> "hash" :>
                   Summary "Hash Table"
                :> QueryParam "tabType" TabType
                :> Get '[JSON] Text

data TableQuery = TableQuery
  { tq_offset       :: Offset
  , tq_limit        :: Limit
  , tq_orderBy      :: OrderBy
  , tq_view         :: TabType
  , tq_query        :: Text
  } deriving (Generic)

type FacetTableResult = TableResult FacetDoc

$(deriveJSON (unPrefix "tq_") ''TableQuery)

instance ToSchema TableQuery where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "tq_")

instance Arbitrary TableQuery where
  arbitrary = elements [TableQuery { tq_offset = 0
                                   , tq_limit = 10
                                   , tq_orderBy = DateAsc
                                   , tq_view = Docs
                                   , tq_query = "electrodes" }]


tableApi :: NodeId -> GargServer TableApi
tableApi id' = getTableApi id'
          :<|> postTableApi id'
          :<|> getTableHashApi id'


getTableApi :: HasNodeError err
            => NodeId
            -> Maybe TabType
            -> Maybe Limit
            -> Maybe Offset
            -> Maybe OrderBy
            -> Maybe Text
            -> Maybe Text
            -> Cmd err (HashedResponse FacetTableResult)
getTableApi cId tabType mLimit mOffset mOrderBy mQuery mYear = do
  -- printDebug "[getTableApi] mQuery" mQuery
  -- printDebug "[getTableApi] mYear" mYear
  t <- getTable cId tabType mOffset mLimit mOrderBy mQuery mYear
  pure $ constructHashedResponse t

postTableApi :: HasNodeError err
             => NodeId -> TableQuery -> Cmd err FacetTableResult
postTableApi cId (TableQuery o l order ft "") = getTable cId (Just ft) (Just o) (Just l) (Just order) Nothing Nothing
postTableApi cId (TableQuery o l order ft q) = case ft of
      Docs  -> searchInCorpus' cId False [q] (Just o) (Just l) (Just order)
      Trash -> searchInCorpus' cId True [q] (Just o) (Just l) (Just order)
      x     -> panic $ "not implemented in tableApi " <> (cs $ show x)

getTableHashApi :: HasNodeError err
                => NodeId -> Maybe TabType -> Cmd err Text
getTableHashApi cId tabType = do
  HashedResponse { hash = h } <- getTableApi cId tabType Nothing Nothing Nothing Nothing Nothing
  pure h

searchInCorpus' :: CorpusId
                -> Bool
                -> [Text]
                -> Maybe Offset
                -> Maybe Limit
                -> Maybe OrderBy
                -> Cmd err FacetTableResult
searchInCorpus' cId t q o l order = do
  docs          <- searchInCorpus cId t q o l order
  countAllDocs  <- searchCountInCorpus cId t q
  pure $ TableResult { tr_docs = docs, tr_count = countAllDocs }


getTable :: HasNodeError err
         => NodeId
         -> Maybe TabType
         -> Maybe Offset
         -> Maybe Limit
         -> Maybe OrderBy
         -> Maybe Text
         -> Maybe Text
         -> Cmd err FacetTableResult
getTable cId ft o l order query year = do
  docs      <- getTable' cId ft o l order query year
  docsCount <- runCountDocuments cId (ft == Just Trash) query year
  pure $ TableResult { tr_docs = docs, tr_count = docsCount }

getTable' :: HasNodeError err
          => NodeId
          -> Maybe TabType
          -> Maybe Offset
          -> Maybe Limit
          -> Maybe OrderBy
          -> Maybe Text
          -> Maybe Text
          -> Cmd err [FacetDoc]
getTable' cId ft o l order query year =
  case ft of
    (Just Docs)      -> runViewDocuments cId False o l order query year
    (Just Trash)     -> runViewDocuments cId True  o l order query year
    (Just MoreFav)   -> moreLike cId o l order IsFav
    (Just MoreTrash) -> moreLike cId o l order IsTrash
    x     -> panic $ "not implemented in getTable: " <> (cs $ show x)


getPair :: ContactId -> Maybe TabType
         -> Maybe Offset  -> Maybe Limit
         -> Maybe OrderBy -> Cmd err [FacetDoc]
getPair cId ft o l order =
  case ft of
    (Just Docs)  -> runViewAuthorsDoc cId False o l order
    (Just Trash) -> runViewAuthorsDoc cId True  o l order
    _     -> panic $ "not implemented: get Pairing" <> (cs $ show ft)
