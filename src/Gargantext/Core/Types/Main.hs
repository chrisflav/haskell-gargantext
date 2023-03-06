{-|
Module      : Gargantext.Core.Types.Main
Description : Short description
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}



{-# LANGUAGE TemplateHaskell   #-}

-----------------------------------------------------------------------
module Gargantext.Core.Types.Main where
------------------------------------------------------------------------

import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson.TH (deriveJSON)
import Data.Either (Either(..))
import Data.Hashable (Hashable)
import Data.Map.Strict (fromList, lookup)
import Data.Maybe (fromMaybe)
import Data.Semigroup (Semigroup(..))
import Data.Swagger
import Data.Text (Text, unpack, pack)
import GHC.Generics (Generic)
import Gargantext.Core
import Gargantext.Core.Utils.Prefix (unPrefix, unPrefixSwagger, wellNamedSchema)
import Gargantext.Database.Admin.Types.Node  -- (NodeType(..), Node, Hyperdata(..))
import Gargantext.Prelude
import Servant.API (FromHttpApiData(..), ToHttpApiData(..))
import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary (Arbitrary, arbitrary)
import Text.Read (readMaybe)

type CorpusName = Text
------------------------------------------------------------------------
data NodeTree = NodeTree { _nt_name      :: Text
                         , _nt_type      :: NodeType
                         , _nt_id        :: NodeId
                         } deriving (Show, Read, Generic)

$(deriveJSON (unPrefix "_nt_") ''NodeTree)
instance ToSchema NodeTree where
  declareNamedSchema = genericDeclareNamedSchema (unPrefixSwagger "_nt_")
------------------------------------------------------------------------

--data Classification = Favorites | MyClassifcation

type TypeId     = Int
-- TODO multiple ListType declaration, remove it
-- data ListType  =  CandidateTerm | StopTerm | MapTerm
data ListType  =  CandidateTerm | StopTerm | MapTerm
  deriving (Generic, Eq, Ord, Show, Read, Enum, Bounded)

instance ToJSON   ListType
instance FromJSON ListType
instance ToSchema ListType
instance ToParamSchema ListType
instance Arbitrary ListType where
  arbitrary = elements [minBound..maxBound]
instance Hashable ListType

instance Semigroup ListType
  where
    MapTerm  <> _             = MapTerm
    _        <> MapTerm       = MapTerm
    StopTerm <> _             = StopTerm
    _        <> StopTerm      = StopTerm
    _        <> _             = CandidateTerm


instance FromHttpApiData ListType where
  parseUrlPiece s = Right s'
    where
      s' = case (readMaybe $ unpack s) of
        Nothing -> panic $ "Cannot read url piece: " <> s
        Just s'' -> s''
instance ToHttpApiData ListType where
  toUrlPiece = pack . show

type ListTypeId = Int

instance HasDBid ListType where
  toDBid   = listTypeId
  fromDBid = (fromMaybe (panic "Instance HasDBid fromDBid ListType")) .  fromListTypeId

-- FIXME Candidate: 0 and Stop : 1
listTypeId :: ListType -> ListTypeId
listTypeId StopTerm      = 0
listTypeId CandidateTerm = 1
listTypeId MapTerm       = 2

fromListTypeId :: ListTypeId -> Maybe ListType
fromListTypeId i = lookup i
                 $ fromList
                 [ (listTypeId l, l)
                 | l <- [StopTerm, CandidateTerm, MapTerm]
                 ]

-- data Metrics = Occurrences | Cooccurrences | Specclusion | Genclusion | Cvalue
--              | TfidfCorpus | TfidfGlobal   | TirankLocal | TirankGlobal

-- | Community Manager Use Case
-- | Favorites Node enable Swap Node with some synonyms for clarity

-- | Then a Node can be a List which has some synonyms

-- | Then a Node can be a Score which has some synonyms

-- Queries
type Limit    = Int
type Offset   = Int
type IsTrash  = Bool

------------------------------------------------------------------------
-- All the Database is structured as a hierarchical Tree
data Tree a = TreeN { _tn_node :: a, _tn_children :: [Tree a] }
  deriving (Show, Read, Eq, Generic, Ord)

$(deriveJSON (unPrefix "_tn_") ''Tree)

instance (Typeable a, ToSchema a) => ToSchema (Tree a) where
  declareNamedSchema = wellNamedSchema "_tn_"

instance Arbitrary (Tree NodeTree) where
  arbitrary = elements [userTree, userTree]


-- data Tree a = NodeT a [Tree a]
-- same as Data.Tree
leafT :: a -> Tree a
leafT x = TreeN x []

------------------------------------------------------------------------
-- Garg Network is a network of all Garg nodes
--gargNetwork = undefined

-- | Garg Node is Database Schema Typed as specification
-- gargNode gathers all the Nodes of all users on one Node
gargNode :: [Tree NodeTree]
gargNode = [userTree]

-- | User Tree simplified
userTree :: Tree NodeTree
userTree = TreeN (NodeTree "user name" NodeUser 1) [annuaireTree, projectTree]

-- | Project Tree
projectTree :: Tree NodeTree
projectTree = TreeN (NodeTree "Project CNRS/IMT" NodeFolder 2) [corpusTree 10 "A", corpusTree 20 "B"]

-- | Corpus Tree
annuaireTree :: Tree NodeTree
annuaireTree = (leafT $ NodeTree "Annuaire" NodeAnnuaire 41)

corpusTree :: NodeId -> Text -> Tree NodeTree
corpusTree nId t  = TreeN (NodeTree ("Corpus " <> t)  NodeCorpus nId) (  [ leafT $ NodeTree "Dashboard" NodeDashboard (nId +1)
                                                                         , leafT $ NodeTree "Graph" NodeGraph (nId +2)
                                                                         ]
--                                                      <> [ leafT $ NodeTree "My lists"  Lists    5]
--                          <> [ leafT (NodeTree "Metrics A" Metrics 6)  ]
--                          <> [ leafT (NodeTree "Class A" Classification 7)]
                          )
