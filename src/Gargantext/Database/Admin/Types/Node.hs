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
{-# LANGUAGE TemplateHaskell            #-}

-- {-# LANGUAGE DuplicateRecordFields #-}

module Gargantext.Database.Admin.Types.Node
  where

import Database.PostgreSQL.Simple.ToRow (ToRow, toRow)
import Codec.Serialise (Serialise())
import Control.Monad (mzero)
import Data.Aeson
import Data.Aeson.TH (deriveJSON)
import qualified Data.Csv as Csv
import Data.Either
import Data.Hashable (Hashable)
import Data.Morpheus.Types (GQLType)
import Data.Swagger
import Data.Text (Text, unpack, pack)
import Data.Time (UTCTime)
import Database.PostgreSQL.Simple.FromField (FromField, fromField, fromJSONField)
import Database.PostgreSQL.Simple.ToField (ToField, toField, toJSONField)
import GHC.Generics (Generic)
import Gargantext.Core.Utils.Prefix (unPrefix, unPrefixSwagger, wellNamedSchema)
import Gargantext.Database.Schema.Context
import Gargantext.Database.Schema.Node
import Gargantext.Prelude
import Gargantext.Prelude.Crypto.Hash (Hash)
import Opaleye (DefaultFromField, defaultFromField, SqlInt4, SqlText, SqlTSVector, Nullable, fromPGSFromField)
import Servant hiding (Context)
import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary
import Test.QuickCheck.Instances.Text ()
import Test.QuickCheck.Instances.Time ()
import Text.Read (read)
import qualified Opaleye as O



type UserId = Int
type MasterUserId = UserId

type NodeTypeId   = Int
type NodeName     = Text
type ContextName  = Text

type TSVector     = Text
type ContextTitle  = Text


------------------------------------------------------------------------
-- | NodePoly indicates that Node has a Polymorphism Type
type Node    json = NodePoly    NodeId (Maybe Hash) NodeTypeId UserId (Maybe ParentId) NodeName UTCTime json
type Context json = ContextPoly NodeId (Maybe Hash) NodeTypeId UserId (Maybe ParentId) ContextTitle UTCTime json

-- | NodeSearch (queries)
-- type NodeSearch json   = NodePolySearch NodeId NodeTypeId UserId (Maybe ParentId) NodeName UTCTime json (Maybe TSVector)

------------------------------------------------------------------------

instance (Typeable hyperdata, ToSchema hyperdata) =>
         ToSchema (NodePoly NodeId Hash NodeTypeId
                            (Maybe UserId)
                            ParentId NodeName
                            UTCTime hyperdata
                  ) where
  declareNamedSchema = wellNamedSchema "_node_"

instance (Typeable hyperdata, ToSchema hyperdata) =>
         ToSchema (NodePoly NodeId Hash NodeTypeId
                            UserId
                            (Maybe ParentId) NodeName
                            UTCTime hyperdata
                  ) where
  declareNamedSchema = wellNamedSchema "_node_"

instance (Typeable hyperdata, ToSchema hyperdata) =>
         ToSchema (NodePoly NodeId (Maybe Hash) NodeTypeId
                            UserId
                            (Maybe ParentId) NodeName
                            UTCTime hyperdata
                  ) where
  declareNamedSchema = wellNamedSchema "_node_"

instance (Typeable hyperdata, ToSchema hyperdata) =>
         ToSchema (NodePolySearch NodeId
                                  NodeTypeId
                                  (Maybe UserId)
                                  ParentId
                                  NodeName
                                  UTCTime
                                  hyperdata
                                  (Maybe TSVector)
                  ) where
  declareNamedSchema = wellNamedSchema "_ns_"

instance (Typeable hyperdata, ToSchema hyperdata) =>
         ToSchema (NodePolySearch NodeId
                                  NodeTypeId
                                  UserId
                                  (Maybe ParentId)
                                  NodeName
                                  UTCTime
                                  hyperdata
                                  (Maybe TSVector)
                  ) where
  declareNamedSchema = wellNamedSchema "_ns_"

instance (Arbitrary nodeId
         ,Arbitrary hashId
         ,Arbitrary toDBid
         ,Arbitrary userId
         ,Arbitrary nodeParentId
         , Arbitrary hyperdata
         ) => Arbitrary (NodePoly nodeId hashId toDBid userId nodeParentId
                                  NodeName UTCTime hyperdata) where
    --arbitrary = Node 1 1 (Just 1) 1 "name" (jour 2018 01 01) (arbitrary) (Just "")
    arbitrary = Node <$> arbitrary <*> arbitrary <*> arbitrary
                     <*> arbitrary <*> arbitrary <*> arbitrary
                     <*> arbitrary <*> arbitrary



instance (Arbitrary hyperdata
         ,Arbitrary nodeId
         ,Arbitrary toDBid
         ,Arbitrary userId
         ,Arbitrary nodeParentId
         ) => Arbitrary (NodePolySearch nodeId
                                        toDBid
                                        userId
                                        nodeParentId
                                        NodeName
                                        UTCTime
                                        hyperdata
                                        (Maybe TSVector)
                        ) where
    --arbitrary = Node 1 1 (Just 1) 1 "name" (jour 2018 01 01) (arbitrary) (Just "")
    arbitrary = NodeSearch <$> arbitrary
                           <*> arbitrary
                           <*> arbitrary
                           <*> arbitrary
                           <*> arbitrary
                           <*> arbitrary
                           <*> arbitrary
                           <*> arbitrary


instance (Arbitrary contextId
         ,Arbitrary hashId
         ,Arbitrary toDBid
         ,Arbitrary userId
         ,Arbitrary contextParentId
         , Arbitrary hyperdata
         ) => Arbitrary (ContextPoly contextId hashId toDBid userId contextParentId
                                  ContextName UTCTime hyperdata) where
    --arbitrary = Node 1 1 (Just 1) 1 "name" (jour 2018 01 01) (arbitrary) (Just "")
    arbitrary = Context <$> arbitrary <*> arbitrary <*> arbitrary
                        <*> arbitrary <*> arbitrary <*> arbitrary
                        <*> arbitrary <*> arbitrary

instance (Arbitrary hyperdata
         ,Arbitrary contextId
         ,Arbitrary toDBid
         ,Arbitrary userId
         ,Arbitrary contextParentId
         ) => Arbitrary (ContextPolySearch contextId
                                        toDBid
                                        userId
                                        contextParentId
                                        ContextName
                                        UTCTime
                                        hyperdata
                                        (Maybe TSVector)
                        ) where
    --arbitrary = Node 1 1 (Just 1) 1 "name" (jour 2018 01 01) (arbitrary) (Just "")
    arbitrary = ContextSearch <$> arbitrary
                              <*> arbitrary
                              <*> arbitrary
                              <*> arbitrary
                              <*> arbitrary
                              <*> arbitrary
                              <*> arbitrary
                              <*> arbitrary




------------------------------------------------------------------------
pgNodeId :: NodeId -> O.Column O.SqlInt4
pgNodeId = O.sqlInt4 . id2int
  where
    id2int :: NodeId -> Int
    id2int (NodeId n) = n

pgContextId :: ContextId -> O.Column O.SqlInt4
pgContextId = pgNodeId

------------------------------------------------------------------------
newtype NodeId = NodeId Int
  deriving (Read, Generic, Num, Eq, Ord, Enum, ToJSONKey, FromJSONKey, ToJSON, FromJSON, Hashable, Csv.ToField)
instance GQLType NodeId
instance Show NodeId where
  show (NodeId n) = "nodeId-" <> show n
instance Serialise NodeId
instance ToField NodeId where
  toField (NodeId n) = toField n
instance ToRow NodeId where
  toRow (NodeId i) = [toField i]

instance FromField NodeId where
  fromField field mdata = do
    n <- fromField field mdata
    if (n :: Int) > 0
       then return $ NodeId n
       else mzero
instance ToSchema NodeId

-- TODO make another type
type ContextId = NodeId

newtype NodeContextId = NodeContextId Int
  deriving (Read, Generic, Num, Eq, Ord, Enum, ToJSONKey, FromJSONKey, ToJSON, FromJSON, Hashable, Csv.ToField)


--instance Csv.ToField NodeId where
--  toField (NodeId nodeId) = Csv.toField nodeId

unNodeId :: NodeId -> Int
unNodeId (NodeId n) = n

------------------------------------------------------------------------
------------------------------------------------------------------------
instance FromHttpApiData NodeId where
  parseUrlPiece n = pure $ NodeId $ (read . cs) n
instance ToHttpApiData NodeId where
  toUrlPiece (NodeId n) = toUrlPiece n
instance ToParamSchema NodeId
instance Arbitrary NodeId where
  arbitrary = NodeId <$> arbitrary

type ParentId    = NodeId
type CorpusId    = NodeId
type CommunityId = NodeId
type ListId      = NodeId
type DocumentId  = NodeId
type DocId       = NodeId
type RootId      = NodeId
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
-- | Then a Node can be either a Folder or a Corpus or a Document
data NodeType = NodeUser
              | NodeFolderPrivate
              | NodeFolderShared | NodeTeam
              | NodeFolderPublic
              | NodeFolder

              -- | NodeAnalysis | NodeCommunity

              | NodeCorpus     | NodeCorpusV3 | NodeTexts | NodeDocument
              | NodeAnnuaire   | NodeContact
              | NodeGraph      | NodePhylo
              | NodeDashboard  -- | NodeChart    | NodeNoteBook
              | NodeList       | NodeModel
              | NodeListCooc

{-
              -- | Metrics
              -- | NodeOccurrences
              -- | Classification
-}

              -- Optional Nodes
              | Notes | Calc | NodeFrameVisio | NodeFrameNotebook
              | NodeFile

  deriving (Show, Read, Eq, Generic, Bounded, Enum)


instance GQLType NodeType
instance FromJSON NodeType
instance ToJSON NodeType
instance FromHttpApiData NodeType where
  parseUrlPiece = Right . read . unpack
instance ToHttpApiData NodeType where
  toUrlPiece = pack . show
instance ToParamSchema NodeType
instance ToSchema      NodeType
instance Arbitrary NodeType where
  arbitrary = elements allNodeTypes
instance FromField NodeType where
  fromField = fromJSONField
instance ToField NodeType where
  toField = toJSONField


allNodeTypes :: [NodeType]
allNodeTypes = [minBound ..]

defaultName :: NodeType -> Text
defaultName NodeUser       = "User"
defaultName NodeContact    = "Contact"

defaultName NodeCorpus     = "Corpus"
defaultName NodeCorpusV3   = "Corpus"
defaultName NodeAnnuaire   = "Annuaire"

defaultName NodeDocument   = "Doc"
defaultName NodeTexts      = "Docs"
defaultName NodeList       = "Terms"
defaultName NodeListCooc   = "List"
defaultName NodeModel      = "Model"

defaultName NodeFolder        = "Folder"
defaultName NodeFolderPrivate = "Private"
defaultName NodeFolderShared  = "Share"
defaultName NodeTeam          = "Team"
defaultName NodeFolderPublic  = "Public"

defaultName NodeDashboard     = "Board"
defaultName NodeGraph         = "Graph"
defaultName NodePhylo         = "Phylo"

defaultName Notes    = "Note"
defaultName Calc     = "Calc"
defaultName NodeFrameVisio    = "Visio"
defaultName NodeFrameNotebook = "Code"

defaultName NodeFile          = "File"



------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------
instance ToSchema Status where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "status_")

------------------------------------------------------------------------
{-
instance FromField (NodeId, Text)
  where
    fromField = fromField'
-}
------------------------------------------------------------------------
instance DefaultFromField SqlTSVector (Maybe TSVector)
  where
    defaultFromField = fromPGSFromField

instance DefaultFromField SqlInt4 (Maybe NodeId)
  where
    defaultFromField = fromPGSFromField

instance DefaultFromField SqlInt4 NodeId
  where
    defaultFromField = fromPGSFromField

instance DefaultFromField (Nullable SqlInt4) NodeId
  where
    defaultFromField = fromPGSFromField

instance (DefaultFromField (Nullable O.SqlTimestamptz) UTCTime)
  where
    defaultFromField = fromPGSFromField

instance DefaultFromField SqlText (Maybe Hash)
  where
    defaultFromField = fromPGSFromField

---------------------------------------------------------------------

context2node :: Context a -> Node a
context2node (Context ci ch ct cu cp cn cd chy) = Node ci ch ct cu cp cn cd chy
