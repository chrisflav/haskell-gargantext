{-|
Module      : Gargantext.Database.Types.Nodes
Description : Main Types of Nodes in Database
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE BangPatterns               #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}

-- {-# LANGUAGE DuplicateRecordFields #-}

module Gargantext.Database.Admin.Types.Node
  where

import Control.Applicative ((<*>))
import Control.Lens hiding (elements, (&))
import Control.Monad (mzero)
import Data.Aeson
import Data.Aeson (Object, toJSON)
import Data.Aeson.TH (deriveJSON)
import Data.Aeson.Types (emptyObject)
import Data.ByteString.Lazy (ByteString)
import Data.Either
import Data.Eq (Eq)
import Data.Monoid (mempty)
import Data.Swagger
import Data.Text (Text, unpack)
import Data.Time (UTCTime)
import Database.PostgreSQL.Simple.FromField (FromField, fromField)
import Database.PostgreSQL.Simple.ToField (ToField, toField, toJSONField)
import GHC.Generics (Generic)
import Gargantext.Core.Utils.Prefix (unPrefix, unPrefixSwagger)
import Gargantext.Database.Prelude (fromField')
import Gargantext.Database.Schema.Node
import Gargantext.Prelude
import Gargantext.Viz.Phylo (Phylo)
import Prelude (Enum, Bounded, minBound, maxBound)
import Servant
import Opaleye (QueryRunnerColumnDefault, queryRunnerColumnDefault, PGInt4, PGJsonb, PGTSVector, Nullable, fieldQueryRunnerColumn)
import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary
import Test.QuickCheck.Instances.Text ()
import Test.QuickCheck.Instances.Time ()
import Text.Read (read)
import Text.Show (Show())
import qualified Opaleye as O


type UserId = Int
type MasterUserId = UserId

------------------------------------------------------------------------
-- | NodePoly indicates that Node has a Polymorphism Type
type Node json   = NodePoly NodeId NodeTypeId UserId (Maybe ParentId) NodeName UTCTime json

-- | NodeSearch (queries)
type NodeSearch json   = NodePolySearch NodeId NodeTypeId UserId (Maybe ParentId) NodeName UTCTime json (Maybe TSVector)

------------------------------------------------------------------------

instance ToSchema hyperdata =>
         ToSchema (NodePoly NodeId NodeTypeId
                            (Maybe UserId)
                            ParentId NodeName
                            UTCTime hyperdata
                  ) where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "_node_")

instance ToSchema hyperdata =>
         ToSchema (NodePoly NodeId NodeTypeId
                            UserId
                            (Maybe ParentId) NodeName
                            UTCTime hyperdata
                  ) where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "_node_")

instance ToSchema hyperdata =>
         ToSchema (NodePolySearch NodeId NodeTypeId
                            (Maybe UserId)
                            ParentId NodeName
                            UTCTime hyperdata (Maybe TSVector)
                  ) where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "_ns_")

instance ToSchema hyperdata =>
         ToSchema (NodePolySearch NodeId NodeTypeId
                            UserId
                            (Maybe ParentId) NodeName
                            UTCTime hyperdata (Maybe TSVector)
                  ) where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "_ns_")

instance (Arbitrary hyperdata
         ,Arbitrary nodeId
         ,Arbitrary nodeTypeId
         ,Arbitrary userId
         ,Arbitrary nodeParentId
         ) => Arbitrary (NodePoly nodeId nodeTypeId userId nodeParentId
                                  NodeName UTCTime hyperdata) where
    --arbitrary = Node 1 1 (Just 1) 1 "name" (jour 2018 01 01) (arbitrary) (Just "")
    arbitrary = Node <$> arbitrary <*> arbitrary <*> arbitrary
                     <*> arbitrary <*> arbitrary <*> arbitrary
                     <*> arbitrary

instance (Arbitrary hyperdata
         ,Arbitrary nodeId
         ,Arbitrary nodeTypeId
         ,Arbitrary userId
         ,Arbitrary nodeParentId
         ) => Arbitrary (NodePolySearch nodeId nodeTypeId userId nodeParentId
                                  NodeName UTCTime hyperdata (Maybe TSVector)) where
    --arbitrary = Node 1 1 (Just 1) 1 "name" (jour 2018 01 01) (arbitrary) (Just "")
    arbitrary = NodeSearch <$> arbitrary <*> arbitrary <*> arbitrary
                     <*> arbitrary <*> arbitrary <*> arbitrary
                     <*> arbitrary <*> arbitrary

------------------------------------------------------------------------
pgNodeId :: NodeId -> O.Column O.PGInt4
pgNodeId = O.pgInt4 . id2int
  where
    id2int :: NodeId -> Int
    id2int (NodeId n) = n

------------------------------------------------------------------------
newtype NodeId = NodeId Int
  deriving (Show, Read, Generic, Num, Eq, Ord, Enum, ToJSONKey, FromJSONKey, ToJSON, FromJSON)

instance ToField NodeId where
  toField (NodeId n) = toField n

instance FromField NodeId where
  fromField field mdata = do
    n <- fromField field mdata
    if (n :: Int) > 0
       then return $ NodeId n
       else mzero

instance ToSchema NodeId

type NodeTypeId   = Int
type NodeName     = Text
type TSVector     = Text

------------------------------------------------------------------------
------------------------------------------------------------------------
instance FromHttpApiData NodeId where
  parseUrlPiece n = pure $ NodeId $ (read . cs) n

instance ToParamSchema NodeId
instance Arbitrary NodeId where
  arbitrary = NodeId <$> arbitrary

type ParentId = NodeId
type CorpusId = NodeId
type ListId   = NodeId
type DocumentId = NodeId
type DocId      = NodeId
type RootId     = NodeId
type MasterCorpusId = CorpusId
type UserCorpusId   = CorpusId

type GraphId  = NodeId
type PhyloId  = NodeId
type AnnuaireId = NodeId
type ContactId  = NodeId

------------------------------------------------------------------------
data Status  = Status { status_failed    :: !Int
                      , status_succeeded :: !Int
                      , status_remaining :: !Int
                      } deriving (Show, Generic)
$(deriveJSON (unPrefix "status_") ''Status)

instance Arbitrary Status where
  arbitrary = Status <$> arbitrary <*> arbitrary <*> arbitrary

------------------------------------------------------------------------
data StatusV3  = StatusV3 { statusV3_error  :: !(Maybe Text)
                          , statusV3_action :: !(Maybe Text)
                      } deriving (Show, Generic)
$(deriveJSON (unPrefix "statusV3_") ''StatusV3)
------------------------------------------------------------------------

-- Only Hyperdata types should be member of this type class.

------------------------------------------------------------------------
data HyperdataDocumentV3 = HyperdataDocumentV3 { hyperdataDocumentV3_publication_day    :: !(Maybe Int)
                                               , hyperdataDocumentV3_language_iso2      :: !(Maybe Text)
                                               , hyperdataDocumentV3_publication_second :: !(Maybe Int)
                                               , hyperdataDocumentV3_publication_minute :: !(Maybe Int)
                                               , hyperdataDocumentV3_publication_month  :: !(Maybe Int)
                                               , hyperdataDocumentV3_publication_hour   :: !(Maybe Int)
                                               , hyperdataDocumentV3_error              :: !(Maybe Text)
                                               , hyperdataDocumentV3_language_iso3      :: !(Maybe Text)
                                               , hyperdataDocumentV3_authors            :: !(Maybe Text)
                                               , hyperdataDocumentV3_publication_year   :: !(Maybe Int)
                                               , hyperdataDocumentV3_publication_date   :: !(Maybe Text)
                                               , hyperdataDocumentV3_language_name      :: !(Maybe Text)
                                               , hyperdataDocumentV3_statuses           :: !(Maybe [StatusV3])
                                               , hyperdataDocumentV3_realdate_full_     :: !(Maybe Text)
                                               , hyperdataDocumentV3_source             :: !(Maybe Text)
                                               , hyperdataDocumentV3_abstract           :: !(Maybe Text)
                                               , hyperdataDocumentV3_title              :: !(Maybe Text)
                                               } deriving (Show, Generic)
$(deriveJSON (unPrefix "hyperdataDocumentV3_") ''HyperdataDocumentV3)

class Hyperdata a
instance Hyperdata HyperdataDocumentV3

------------------------------------------------------------------------
data HyperdataDocument = HyperdataDocument { _hyperdataDocument_bdd                :: !(Maybe Text)
                                           , _hyperdataDocument_doi                :: !(Maybe Text)
                                           , _hyperdataDocument_url                :: !(Maybe Text)
                                           , _hyperdataDocument_uniqId             :: !(Maybe Text)
                                           , _hyperdataDocument_uniqIdBdd          :: !(Maybe Text)
                                           , _hyperdataDocument_page               :: !(Maybe Int)
                                           , _hyperdataDocument_title              :: !(Maybe Text)
                                           , _hyperdataDocument_authors            :: !(Maybe Text)
                                           , _hyperdataDocument_institutes         :: !(Maybe Text)
                                           , _hyperdataDocument_source             :: !(Maybe Text)
                                           , _hyperdataDocument_abstract           :: !(Maybe Text)
                                           , _hyperdataDocument_publication_date   :: !(Maybe Text)
                                           , _hyperdataDocument_publication_year   :: !(Maybe Int)
                                           , _hyperdataDocument_publication_month  :: !(Maybe Int)
                                           , _hyperdataDocument_publication_day    :: !(Maybe Int)
                                           , _hyperdataDocument_publication_hour   :: !(Maybe Int)
                                           , _hyperdataDocument_publication_minute :: !(Maybe Int)
                                           , _hyperdataDocument_publication_second :: !(Maybe Int)
                                           , _hyperdataDocument_language_iso2      :: !(Maybe Text)
                                           } deriving (Show, Generic)

$(deriveJSON (unPrefix "_hyperdataDocument_") ''HyperdataDocument)
$(makeLenses ''HyperdataDocument)

class ToHyperdataDocument a where
  toHyperdataDocument :: a -> HyperdataDocument

instance ToHyperdataDocument HyperdataDocument
  where
    toHyperdataDocument = identity

instance Eq HyperdataDocument where
  (==) h1 h2 = (==) (_hyperdataDocument_uniqId h1) (_hyperdataDocument_uniqId h2)

instance Ord HyperdataDocument where
  compare h1 h2 = compare (_hyperdataDocument_publication_date h1) (_hyperdataDocument_publication_date h2)

instance Hyperdata HyperdataDocument

instance ToField HyperdataDocument where
  toField = toJSONField

instance Arbitrary HyperdataDocument where
    arbitrary = elements arbitraryHyperdataDocuments

arbitraryHyperdataDocuments :: [HyperdataDocument]
arbitraryHyperdataDocuments =
  map toHyperdataDocument' ([ ("AI is big but less than crypto", "Troll System journal")
                            , ("Crypto is big but less than AI", "System Troll review" )
                            , ("Science is magic"              , "Closed Source review")
                            , ("Open science for all"          , "No Time"             )
                            , ("Closed science for me"         , "No Space"            )
                            ] :: [(Text, Text)])
  where
    toHyperdataDocument' (t1,t2) =
      HyperdataDocument Nothing Nothing Nothing Nothing Nothing Nothing (Just t1)
                      Nothing Nothing (Just t2) Nothing Nothing Nothing Nothing Nothing 
                      Nothing Nothing Nothing   Nothing

------------------------------------------------------------------------
data LanguageNodes = LanguageNodes { languageNodes___unknown__ :: [Int]}
    deriving (Show, Generic)
$(deriveJSON (unPrefix "languageNodes_") ''LanguageNodes)

------------------------------------------------------------------------
-- level: debug | dev  (fatal = critical)
data EventLevel = CRITICAL | FATAL | ERROR | WARNING | INFO | DEBUG
  deriving (Show, Generic, Enum, Bounded)

instance FromJSON EventLevel
instance ToJSON EventLevel

instance Arbitrary EventLevel where
  arbitrary = elements [minBound..maxBound]

instance ToSchema EventLevel where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy

------------------------------------------------------------------------
data Event = Event { event_level   :: !EventLevel
                   , event_message :: !Text
                   , event_date    :: !UTCTime
            } deriving (Show, Generic)
$(deriveJSON (unPrefix "event_") ''Event)

instance Arbitrary Event where
  arbitrary = Event <$> arbitrary <*> arbitrary <*> arbitrary

instance ToSchema Event where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "event_")

------------------------------------------------------------------------
data Resource = Resource { resource_path    :: !(Maybe Text)
                         , resource_scraper :: !(Maybe Text)
                         , resource_query   :: !(Maybe Text)
                         , resource_events  :: !([Event])
                         , resource_status  :: !Status
                         , resource_date    :: !UTCTime
                         } deriving (Show, Generic)
$(deriveJSON (unPrefix "resource_") ''Resource)

instance Arbitrary Resource where
    arbitrary = Resource <$> arbitrary
                         <*> arbitrary
                         <*> arbitrary
                         <*> arbitrary
                         <*> arbitrary
                         <*> arbitrary

instance ToSchema Resource where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "resource_")

------------------------------------------------------------------------
------------------------------------------------------------------------
data Chart =
    CDocsHistogram
  | CAuthorsPie
  | CInstitutesTree
  | CTermsMetrics
  deriving (Generic, Show, Eq)
instance ToJSON Chart
instance FromJSON Chart
instance ToSchema Chart


data CodeType = JSON | Markdown | Haskell
  deriving (Generic)
instance ToJSON CodeType
instance FromJSON CodeType
instance ToSchema CodeType

------------------------------------------------------------------------
data CorpusField = MarkdownField { _cf_text :: !Text }
                  | JsonField { _cf_title :: !Text
                              , _cf_desc  :: !Text
                              , _cf_query :: !Text
                              , _cf_authors :: !Text
                              -- , _cf_resources :: ![Resource]
                              } 
                  | HaskellField { _cf_haskell :: !Text }
                  deriving (Generic)

$(deriveJSON (unPrefix "_cf_") ''CorpusField)
$(makeLenses ''CorpusField)

defaultCorpusField :: CorpusField
defaultCorpusField = MarkdownField "# title"

instance ToSchema CorpusField where
  declareNamedSchema proxy =
    genericDeclareNamedSchema (unPrefixSwagger "_cf_") proxy
    & mapped.schema.description ?~ "CorpusField"
    & mapped.schema.example ?~ toJSON defaultCorpusField

------------------------------------------------------------------------
data HyperdataField a =
  HyperdataField { _hf_type :: !CodeType
                 , _hf_name :: !Text
                 , _hf_data :: !a
                 } deriving (Generic)
$(deriveJSON (unPrefix "_hf_") ''HyperdataField)
$(makeLenses ''HyperdataField)

defaultHyperdataField :: HyperdataField CorpusField
defaultHyperdataField = HyperdataField Markdown "name" defaultCorpusField

instance (ToSchema a) => ToSchema (HyperdataField a) where
  declareNamedSchema =
    genericDeclareNamedSchema (unPrefixSwagger "_hf_")
    -- & mapped.schema.description ?~ "HyperdataField"
    -- & mapped.schema.example ?~ toJSON defaultHyperdataField

------------------------------------------------------------------------
data HyperdataCorpus =
  HyperdataCorpus { _hc_fields :: ![HyperdataField CorpusField] }
    deriving (Generic)
$(deriveJSON (unPrefix "_hc_") ''HyperdataCorpus)
$(makeLenses ''HyperdataCorpus)

instance Hyperdata HyperdataCorpus

corpusExample :: ByteString
corpusExample = "" -- TODO

defaultCorpus :: HyperdataCorpus
defaultCorpus = HyperdataCorpus [
    HyperdataField JSON "Mandatory fields" (JsonField "Title" "Descr" "Bool query" "Authors")
  , HyperdataField Markdown "Optional Text" (MarkdownField "# title\n## subtitle")
  ]

hyperdataCorpus :: HyperdataCorpus
hyperdataCorpus = case decode corpusExample of
  Just hp -> hp
  Nothing -> defaultCorpus

instance Arbitrary HyperdataCorpus where
    arbitrary = pure hyperdataCorpus -- TODO

------------------------------------------------------------------------
data HyperdataList =
  HyperdataList { hd_list :: !(Maybe Text)
                } deriving (Show, Generic)
$(deriveJSON (unPrefix "hd_") ''HyperdataList)

instance Hyperdata HyperdataList

------------------------------------------------------------------------
data HyperdataAnnuaire = HyperdataAnnuaire { hyperdataAnnuaire_title        :: !(Maybe Text)
                                           , hyperdataAnnuaire_desc         :: !(Maybe Text)
                                           } deriving (Show, Generic)
$(deriveJSON (unPrefix "hyperdataAnnuaire_") ''HyperdataAnnuaire)

instance Hyperdata HyperdataAnnuaire

hyperdataAnnuaire :: HyperdataAnnuaire
hyperdataAnnuaire = HyperdataAnnuaire (Just "Annuaire Title") (Just "Annuaire Description")

instance Arbitrary HyperdataAnnuaire where
    arbitrary = pure hyperdataAnnuaire -- TODO

------------------------------------------------------------------------
newtype HyperdataAny = HyperdataAny Object
  deriving (Show, Generic, ToJSON, FromJSON)

instance Hyperdata HyperdataAny

instance Arbitrary HyperdataAny where
    arbitrary = pure $ HyperdataAny mempty -- TODO produce arbitrary objects
------------------------------------------------------------------------

{-
instance Arbitrary HyperdataList' where
  arbitrary = elements [HyperdataList' (Just "from list A")]
-}

                      ----
data HyperdataListModel =
  HyperdataListModel { _hlm_params  :: !(Int, Int)
                     , _hlm_path    :: !Text
                     , _hlm_score   :: !(Maybe Double)
                     } deriving (Show, Generic)

instance Hyperdata HyperdataListModel
instance Arbitrary HyperdataListModel where
  arbitrary = elements [HyperdataListModel (100,100) "models/example.model" Nothing]

$(deriveJSON (unPrefix "_hlm_") ''HyperdataListModel)
$(makeLenses ''HyperdataListModel)

------------------------------------------------------------------------
data HyperdataScore = HyperdataScore { hyperdataScore_preferences   :: !(Maybe Text)
                                   } deriving (Show, Generic)
$(deriveJSON (unPrefix "hyperdataScore_") ''HyperdataScore)

instance Hyperdata HyperdataScore

------------------------------------------------------------------------
data HyperdataResource = HyperdataResource { hyperdataResource_preferences   :: !(Maybe Text)
                                   } deriving (Show, Generic)
$(deriveJSON (unPrefix "hyperdataResource_") ''HyperdataResource)

instance Hyperdata HyperdataResource

------------------------------------------------------------------------
data HyperdataDashboard = HyperdataDashboard { hyperdataDashboard_preferences   :: !(Maybe Text)
                                             , hyperdataDashboard_charts        :: ![Chart]
                                   } deriving (Show, Generic)
$(deriveJSON (unPrefix "hyperdataDashboard_") ''HyperdataDashboard)

instance Hyperdata HyperdataDashboard

------------------------------------------------------------------------
-- TODO add the Graph Structure here
data HyperdataPhylo = HyperdataPhylo { hyperdataPhylo_preferences   :: !(Maybe Text)
                                     , hyperdataPhylo_data          :: !(Maybe Phylo)
                                   } deriving (Show, Generic)
$(deriveJSON (unPrefix "hyperdataPhylo_") ''HyperdataPhylo)

instance Hyperdata HyperdataPhylo

------------------------------------------------------------------------
-- | TODO FEATURE: Notebook saved in the node
data HyperdataNotebook = HyperdataNotebook { hyperdataNotebook_preferences   :: !(Maybe Text)
                                   } deriving (Show, Generic)
$(deriveJSON (unPrefix "hyperdataNotebook_") ''HyperdataNotebook)

instance Hyperdata HyperdataNotebook


-- | TODO CLEAN
data HyperData = HyperdataTexts { hd_preferences :: Maybe Text }
               | HyperdataList' { hd_preferences :: Maybe Text}
  deriving (Show, Generic)

$(deriveJSON (unPrefix "hd_") ''HyperData)

instance Hyperdata HyperData

------------------------------------------------------------------------
-- | Then a Node can be either a Folder or a Corpus or a Document
data NodeType = NodeUser
              | NodeFolderPrivate
              | NodeFolderShared | NodeTeam
              | NodeFolderPublic
              | NodeFolder

              | NodeCorpus     | NodeCorpusV3 | NodeTexts | NodeDocument
              | NodeAnnuaire   | NodeContact
              | NodeGraph      | NodePhylo
              | NodeDashboard  | NodeChart    | NodeNoteBook
              | NodeList       | NodeListModel
              | NodeListCooc
  deriving (Show, Read, Eq, Generic, Bounded, Enum)


{-
              -- | Metrics
              -- | NodeOccurrences
              -- | Classification
-}

allNodeTypes :: [NodeType]
allNodeTypes = [minBound ..]

instance FromJSON NodeType
instance ToJSON NodeType

instance FromHttpApiData NodeType
  where
      parseUrlPiece = Right . read . unpack

instance ToParamSchema NodeType
instance ToSchema      NodeType

------------------------------------------------------------------------
------------------------------------------------------------------------
hyperdataDocument :: HyperdataDocument
hyperdataDocument = case decode docExample of
                      Just hp -> hp
                      Nothing -> HyperdataDocument Nothing Nothing Nothing Nothing
                                                   Nothing Nothing Nothing Nothing
                                                   Nothing Nothing Nothing Nothing
                                                   Nothing Nothing Nothing Nothing
                                                   Nothing Nothing Nothing
docExample :: ByteString
docExample = "{\"doi\":\"sdfds\",\"publication_day\":6,\"language_iso2\":\"en\",\"publication_minute\":0,\"publication_month\":7,\"language_iso3\":\"eng\",\"publication_second\":0,\"authors\":\"Nils Hovdenak, Kjell Haram\",\"publication_year\":2012,\"publication_date\":\"2012-07-06 00:00:00+00:00\",\"language_name\":\"English\",\"realdate_full_\":\"2012 01 12\",\"source\":\"European journal of obstetrics, gynecology, and reproductive biology\",\"abstract\":\"The literature was searched for publications on minerals and vitamins during pregnancy and the possible influence of supplements on pregnancy outcome.\",\"title\":\"Influence of mineral and vitamin supplements on pregnancy outcome.\",\"publication_hour\":0}"

------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------

instance ToSchema HyperdataCorpus where
  declareNamedSchema proxy =
    genericDeclareNamedSchema (unPrefixSwagger "_hc_") proxy
    & mapped.schema.description ?~ "Corpus"
    & mapped.schema.example ?~ toJSON hyperdataCorpus

instance ToSchema HyperdataAnnuaire where
  declareNamedSchema proxy =
    genericDeclareNamedSchema (unPrefixSwagger "hyperdataAnnuaire_") proxy
    & mapped.schema.description ?~ "an annuaire"
    & mapped.schema.example ?~ toJSON hyperdataAnnuaire

instance ToSchema HyperdataDocument where
  declareNamedSchema proxy =
    genericDeclareNamedSchema (unPrefixSwagger "_hyperdataDocument_") proxy
    & mapped.schema.description ?~ "a document"
    & mapped.schema.example ?~ toJSON hyperdataDocument

instance ToSchema HyperdataAny where
  declareNamedSchema proxy =
    pure $ genericNameSchema defaultSchemaOptions proxy mempty
             & schema.description ?~ "a node"
             & schema.example ?~ emptyObject -- TODO

instance ToSchema Status where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "status_")

------------------------------------------------------------------------

instance FromField HyperdataAny where
    fromField = fromField'

instance FromField HyperdataCorpus
  where
    fromField = fromField'

instance FromField HyperdataDocument
  where
    fromField = fromField'

instance FromField HyperdataDocumentV3
  where
    fromField = fromField'

instance FromField HyperData
  where
    fromField = fromField'

instance FromField HyperdataListModel
  where
    fromField = fromField'

instance FromField HyperdataPhylo
  where
    fromField = fromField'

instance FromField HyperdataAnnuaire
  where
    fromField = fromField'

instance FromField HyperdataList
  where
    fromField = fromField'

instance FromField (NodeId, Text)
  where
    fromField = fromField'
------------------------------------------------------------------------
instance QueryRunnerColumnDefault PGJsonb HyperdataAny
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperdataList
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperData
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperdataDocument
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperdataDocumentV3
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperdataCorpus
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperdataListModel
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperdataPhylo
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGJsonb HyperdataAnnuaire
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGTSVector (Maybe TSVector)
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGInt4 (Maybe NodeId)
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault PGInt4 NodeId
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn

instance QueryRunnerColumnDefault (Nullable PGInt4) NodeId
  where
    queryRunnerColumnDefault = fieldQueryRunnerColumn




