{-|
Module      : Gargantext.API.Node.Corpus.New
Description : New corpus API
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

New corpus means either:
- new corpus
- new data in existing corpus
-}

{-# LANGUAGE TemplateHaskell    #-}
{-# LANGUAGE TypeOperators      #-}

module Gargantext.API.Node.Corpus.New
      where

import Conduit
import Control.Lens hiding (elements, Empty)
import Data.Aeson
import Data.Aeson.TH (deriveJSON)
import qualified Data.ByteString.Base64 as BSB64
import Data.Conduit.Internal (zipSources)
import Data.Either
import Data.Maybe (fromMaybe)
import Data.Swagger
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Servant
import Servant.Job.Utils (jsonOptions)
-- import Servant.Multipart
import qualified Data.Text.Encoding as TE
-- import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary

import Gargantext.API.Admin.Orchestrator.Types (JobLog(..), AsyncJobs, ScraperEvent(..), scst_events)
import Gargantext.API.Admin.Types (HasSettings)
import Gargantext.API.Job (addEvent, jobLogSuccess, jobLogFailTotal)
import Gargantext.API.Node.Corpus.New.Types
import Gargantext.API.Node.Corpus.Searx
import Gargantext.API.Node.Corpus.Types
import Gargantext.API.Node.Types
import Gargantext.Core (Lang(..){-, allLangs-})
import Gargantext.Core.Text.List.Social (FlowSocialListWith(..))
import Gargantext.Core.Types.Individu (User(..))
import Gargantext.Core.Utils.Prefix (unPrefix, unPrefixSwagger)
import Gargantext.Database.Action.Flow (flowCorpus, getDataText, flowDataText, TermType(..){-, allDataOrigins-})
import Gargantext.Database.Action.Flow.Types (FlowCmdM)
import Gargantext.Database.Action.Mail (sendMail)
import Gargantext.Database.Action.Node (mkNodeWithParent)
import Gargantext.Database.Action.User (getUserId)
import Gargantext.Database.Admin.Types.Hyperdata
import Gargantext.Database.Admin.Types.Node (CorpusId, NodeType(..), UserId)
import Gargantext.Database.Prelude (hasConfig)
import Gargantext.Database.Query.Table.Node (getNodeWith)
import Gargantext.Database.Query.Table.Node.UpdateOpaleye (updateHyperdata)
import Gargantext.Database.Schema.Node (node_hyperdata)
import Gargantext.Prelude
import Gargantext.Prelude.Config (gc_max_docs_parsers)
import qualified Gargantext.Core.Text.Corpus.API as API
import qualified Gargantext.Core.Text.Corpus.Parsers as Parser (FileType(..), parseFormatC)
import qualified Gargantext.Database.GargDB as GargDB
------------------------------------------------------------------------
{-
data Query = Query { query_query      :: Text
                   , query_node_id    :: Int
                   , query_lang       :: Lang
                   , query_databases  :: [DataOrigin]
                   }
                   deriving (Eq, Generic)

deriveJSON (unPrefix "query_") 'Query

instance Arbitrary Query where
    arbitrary = elements [ Query q n la fs
                         | q <- ["honeybee* AND collapse"
                                ,"covid 19"
                                ]
                         , n <- [0..10]
                         , la <- allLangs
                         , fs <- take 3 $ repeat allDataOrigins
                         ]

instance ToSchema Query where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "query_")
-}

------------------------------------------------------------------------

{-
type Api = PostApi
        :<|> GetApi

type PostApi = Summary "New Corpus endpoint"
             :> ReqBody '[JSON] Query
             :> Post    '[JSON] CorpusId
type GetApi = Get '[JSON] ApiInfo
-}

-- | TODO manage several apis
-- TODO-ACCESS
-- TODO this is only the POST
{-
api :: (FlowCmdM env err m) => UserId -> Query -> m CorpusId
api uid (Query q _ as) = do
  cId <- case head as of
    Nothing      -> flowCorpusSearchInDatabase (UserDBId uid) EN q
    Just API.All -> flowCorpusSearchInDatabase (UserDBId uid) EN q
    Just a   -> do
      docs <- liftBase $ API.get a q (Just 1000)
      cId' <- flowCorpus (UserDBId uid) (Left q) (Multi EN) [docs]
      pure cId'

  pure cId
-}

------------------------------------------------
-- TODO use this route for Client implementation
data ApiInfo = ApiInfo { api_info :: [API.ExternalAPIs]}
  deriving (Generic)
instance Arbitrary ApiInfo where
  arbitrary = ApiInfo <$> arbitrary

deriveJSON (unPrefix "") 'ApiInfo

instance ToSchema ApiInfo

info :: FlowCmdM env err m => UserId -> m ApiInfo
info _u = do
  ext <- API.externalAPIs

  pure $ ApiInfo ext

------------------------------------------------------------------------
------------------------------------------------------------------------
data WithQuery = WithQuery
  { _wq_query        :: !Text
  , _wq_databases    :: !Database
  , _wq_datafield    :: !(Maybe Datafield)
  , _wq_lang         :: !Lang
  , _wq_node_id      :: !Int
  , _wq_flowListWith :: !FlowSocialListWith
  }
  deriving Generic

makeLenses ''WithQuery
instance FromJSON WithQuery where
  parseJSON = genericParseJSON $ jsonOptions "_wq_"
instance ToJSON WithQuery where
  toJSON = genericToJSON $ jsonOptions "_wq_"
instance ToSchema WithQuery where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "_wq_")

------------------------------------------------------------------------

type AddWithQuery = Summary "Add with Query to corpus endpoint"
   :> "corpus"
     :> Capture "corpus_id" CorpusId
   :> "query"
     :> AsyncJobs JobLog '[JSON] WithQuery JobLog

{-
type AddWithFile = Summary "Add with MultipartData to corpus endpoint"
   :> "corpus"
     :> Capture "corpus_id" CorpusId
   :> "add"
   :> "file"
     :> MultipartForm Mem (MultipartData Mem)
     :> QueryParam "fileType"  FileType
   :> "async"
     :> AsyncJobs JobLog '[JSON] () JobLog
-}


------------------------------------------------------------------------
-- TODO WithQuery also has a corpus id


addToCorpusWithQuery :: FlowCmdM env err m
                       => User
                       -> CorpusId
                       -> WithQuery
                       -> Maybe Integer
                       -> (JobLog -> m ())
                       -> m JobLog
addToCorpusWithQuery user cid (WithQuery { _wq_query = q
                                         , _wq_databases = dbs
                                         , _wq_datafield = datafield
                                         , _wq_lang = l
                                         , _wq_flowListWith = flw }) maybeLimit logStatus = do
  -- TODO ...
  logStatus JobLog { _scst_succeeded = Just 0
                   , _scst_failed    = Just 0
                   , _scst_remaining = Just 3
                   , _scst_events    = Just []
                   }
  printDebug "[addToCorpusWithQuery] (cid, dbs)" (cid, dbs)
  printDebug "[addToCorpusWithQuery] datafield" datafield
  printDebug "[addToCorpusWithQuery] flowListWith" flw

  case datafield of
    Just Web -> do
      printDebug "[addToCorpusWithQuery] processing web request" datafield

      _ <- triggerSearxSearch user cid q l logStatus

      pure JobLog { _scst_succeeded = Just 3
                  , _scst_failed    = Just 0
                  , _scst_remaining = Just 0
                  , _scst_events    = Just []
                  }

    _ -> do
      -- TODO add cid
      -- TODO if cid is folder -> create Corpus
      --      if cid is corpus -> add to corpus
      --      if cid is root   -> create corpus in Private
      printDebug "[G.A.N.C.New] getDataText with query" q
      databaseOrigin <- database2origin dbs
      eTxts <- mapM (\db -> getDataText db (Multi l) q maybeLimit) [databaseOrigin]

      let lTxts = lefts eTxts
      printDebug "[G.A.N.C.New] lTxts" lTxts
      case lTxts of
        [] -> do
          let txts = rights eTxts
          -- TODO Sum lenghts of each txt elements
          logStatus $ JobLog { _scst_succeeded = Just 2
                             , _scst_failed    = Just 0
                             , _scst_remaining = Just $ 1 + length txts
                             , _scst_events    = Just []
                             }

          cids <- mapM (\txt -> do
                           flowDataText user txt (Multi l) cid Nothing logStatus) txts
          printDebug "corpus id" cids
          printDebug "sending email" ("xxxxxxxxxxxxxxxxxxxxx" :: Text)
          sendMail user
          -- TODO ...
          pure JobLog { _scst_succeeded = Just 3
                      , _scst_failed    = Just 0
                      , _scst_remaining = Just 0
                      , _scst_events    = Just []
                      }

        (err:_) -> do
          printDebug "Error: " err
          let jl = addEvent "ERROR" (T.pack $ show err) $
                JobLog { _scst_succeeded = Just 2
                       , _scst_failed    = Just 1
                       , _scst_remaining = Just 0
                       , _scst_events    = Just []
                       }
          logStatus jl
          pure jl


type AddWithForm = Summary "Add with FormUrlEncoded to corpus endpoint"
   :> "corpus"
     :> Capture "corpus_id" CorpusId
   :> "add"
   :> "form"
   :> "async"
     :> AsyncJobs JobLog '[FormUrlEncoded] NewWithForm JobLog

addToCorpusWithForm :: (FlowCmdM env err m)
                    => User
                    -> CorpusId
                    -> NewWithForm
                    -> (JobLog -> m ())
                    -> JobLog
                    -> m JobLog
addToCorpusWithForm user cid (NewWithForm ft ff d l _n) logStatus jobLog = do
  printDebug "[addToCorpusWithForm] Parsing corpus: " cid
  printDebug "[addToCorpusWithForm] fileType" ft
  printDebug "[addToCorpusWithForm] fileFormat" ff
  logStatus jobLog
  limit' <- view $ hasConfig . gc_max_docs_parsers
  let limit = fromIntegral limit' :: Integer
  let
    parseC = case ft of
      CSV_HAL   -> Parser.parseFormatC Parser.CsvHal
      CSV       -> Parser.parseFormatC Parser.CsvGargV3
      WOS       -> Parser.parseFormatC Parser.WOS
      PresseRIS -> Parser.parseFormatC Parser.RisPresse

  -- TODO granularity of the logStatus
  let data' = case ff of
        Plain -> cs d
        ZIP   -> case BSB64.decode $ TE.encodeUtf8 d of
          Left err -> panic $ T.pack "[addToCorpusWithForm] error decoding base64: " <> T.pack err
          Right decoded -> decoded
  eDocsC <- liftBase $ parseC ff data'
  case eDocsC of
    Right (mCount, docsC) -> do
      -- TODO Add progress (jobStatus) update for docs - this is a
      -- long action

      let docsC' = zipSources (yieldMany [1..]) docsC
                  .| mapMC (\(idx, doc) ->
                        if idx > limit then do
                          --printDebug "[addToCorpusWithForm] number of docs exceeds the limit" (show limit)
                          let panicMsg' = [ "[addToCorpusWithForm] number of docs "
                                          , "exceeds the MAX_DOCS_PARSERS limit ("
                                          , show limit
                                          , ")" ]
                          let panicMsg = T.concat $ T.pack <$> panicMsg'
                          --logStatus $ jobLogFailTotalWithMessage panicMsg jobLog
                          panic panicMsg
                        else
                          pure doc)
                  .| mapC toHyperdataDocument

      --printDebug "Parsing corpus finished : " cid
      --logStatus jobLog2

      --printDebug "Starting extraction     : " cid
      -- TODO granularity of the logStatus
      printDebug "flowCorpus with (corpus_id, lang)" (cid, l)

      _cid' <- flowCorpus user
                          (Right [cid])
                          (Multi $ fromMaybe EN l)
                          Nothing
                          --(Just $ fromIntegral $ length docs, docsC')
                          (mCount, transPipe liftBase docsC') -- TODO fix number of docs
                          --(map (map toHyperdataDocument) docs)
                          logStatus

      printDebug "Extraction finished   : " cid
      printDebug "sending email" ("xxxxxxxxxxxxxxxxxxxxx" :: Text)
      -- TODO uncomment this
      --sendMail user

      logStatus jobLog3
      pure jobLog3
    Left e -> do
      printDebug "[addToCorpusWithForm] parse error" e

      let evt = ScraperEvent { _scev_message = Just $ T.pack e
                             , _scev_level = Just "ERROR"
                             , _scev_date = Nothing }

      logStatus $ over (scst_events . _Just) (\evt' -> evt' <> [evt]) jobLogE
      pure jobLogE
    where
      jobLog2 = jobLogSuccess jobLog
      jobLog3 = jobLogSuccess jobLog2
      jobLogE = jobLogFailTotal jobLog

{-
addToCorpusWithFile :: FlowCmdM env err m
                    => CorpusId
                    -> MultipartData Mem
                    -> Maybe FileType
                    -> (JobLog -> m ())
                    -> m JobLog
addToCorpusWithFile cid input filetype logStatus = do
  logStatus JobLog { _scst_succeeded = Just 10
                          , _scst_failed    = Just 2
                          , _scst_remaining = Just 138
                          , _scst_events    = Just []
                          }
  printDebug "addToCorpusWithFile" cid
  _h <- postUpload cid filetype input

  pure      JobLog { _scst_succeeded = Just 137
                          , _scst_failed    = Just 13
                          , _scst_remaining = Just 0
                          , _scst_events    = Just []
                          }
-}



type AddWithFile = Summary "Add with FileUrlEncoded to corpus endpoint"
   :> "corpus"
     :> Capture "corpus_id" CorpusId
   :> "add"
   :> "file"
   :> "async"
     :> AsyncJobs JobLog '[FormUrlEncoded] NewWithFile JobLog

addToCorpusWithFile :: (HasSettings env, FlowCmdM env err m)
                    => User
                    -> CorpusId
                    -> NewWithFile
                    -> (JobLog -> m ())
                    -> m JobLog
addToCorpusWithFile user cid nwf@(NewWithFile _d _l fName) logStatus = do

  printDebug "[addToCorpusWithFile] Uploading file to corpus: " cid
  logStatus JobLog { _scst_succeeded = Just 0
                   , _scst_failed    = Just 0
                   , _scst_remaining = Just 1
                   , _scst_events    = Just []
                   }

  fPath <- GargDB.writeFile nwf
  printDebug "[addToCorpusWithFile] File saved as: " fPath

  uId <- getUserId user
  nIds <- mkNodeWithParent NodeFile (Just cid) uId fName

  _ <- case nIds of
    [nId] -> do
        node <- getNodeWith nId (Proxy :: Proxy HyperdataFile)
        let hl = node ^. node_hyperdata
        _ <- updateHyperdata nId $ hl { _hff_name = fName
                                      , _hff_path = T.pack fPath }

        printDebug "[addToCorpusWithFile] Created node with id: " nId
    _     -> pure ()

  printDebug "[addToCorpusWithFile] File upload to corpus finished: " cid

  printDebug "sending email" ("xxxxxxxxxxxxxxxxxxxxx" :: Text)
  sendMail user

  pure $ JobLog { _scst_succeeded = Just 1
                , _scst_failed    = Just 0
                , _scst_remaining = Just 0
                , _scst_events    = Just []
                }
