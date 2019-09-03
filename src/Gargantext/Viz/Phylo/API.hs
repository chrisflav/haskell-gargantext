{-|
Module      : Gargantext.Viz.Phylo.API
Description : Phylo API
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE NoImplicitPrelude  #-}
{-# LANGUAGE OverloadedStrings  #-}   -- allows to write Text literals
{-# LANGUAGE OverloadedLists    #-}   -- allows to write Map and HashMap as lists
{-# LANGUAGE TypeOperators      #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gargantext.Viz.Phylo.API
  where

import Data.String.Conversions
--import Control.Monad.Reader (ask)
import qualified Data.ByteString as DB
import qualified Data.ByteString.Lazy as DBL
import Data.Swagger
import Gargantext.API.Types
import Gargantext.API.Utils (swaggerOptions)
import Gargantext.Database.Types.Node (PhyloId, ListId, CorpusId)
import Gargantext.Database.Schema.Node (insertNodes, nodePhyloW, getNodePhylo)
import Gargantext.Database.Types.Node -- (NodePhylo(..))
import Gargantext.Prelude
import Gargantext.Viz.Phylo
import Gargantext.Viz.Phylo.Main
import Gargantext.Viz.Phylo.Example
import Gargantext.API.Ngrams (TODO(..))
import Servant
import Test.QuickCheck (elements)
import Test.QuickCheck.Arbitrary (Arbitrary, arbitrary)
import Web.HttpApiData (parseUrlPiece, readTextData)
import Control.Monad.IO.Class (liftIO)
import Network.HTTP.Media ((//), (/:))

------------------------------------------------------------------------
type PhyloAPI = Summary "Phylo API"
              :> GetPhylo
        --    :<|> PutPhylo
            :<|> PostPhylo


phyloAPI :: PhyloId -> UserId -> GargServer PhyloAPI
phyloAPI n u = getPhylo  n
        :<|> postPhylo n u
        -- :<|> putPhylo  n
        -- :<|> deletePhylo  n

newtype SVG = SVG DB.ByteString

instance ToSchema SVG
  where
    declareNamedSchema _ = declareNamedSchema (Proxy :: Proxy TODO)

instance Show SVG where
  show (SVG a) = show a

instance Accept SVG where
   contentType _ = "SVG" // "image/svg+xml" /: ("charset", "utf-8")

instance Show a => MimeRender PlainText a where
   mimeRender _ val = cs ("" <> show val)

instance MimeRender SVG SVG where
   mimeRender _ (SVG s) = DBL.fromStrict s

------------------------------------------------------------------------
type GetPhylo =  QueryParam "listId"      ListId
              :> QueryParam "level"       Level
              :> QueryParam "minSizeBranch" MinSizeBranch
   {-           :> QueryParam "filiation"   Filiation
              :> QueryParam "childs"      Bool
              :> QueryParam "depth"       Level
              :> QueryParam "metrics"    [Metric]
              :> QueryParam "periodsInf" Int
              :> QueryParam "periodsSup" Int
              :> QueryParam "minNodes"   Int
              :> QueryParam "taggers"    [Tagger]
              :> QueryParam "sort"       Sort
              :> QueryParam "order"      Order
              :> QueryParam "export"    ExportMode
              :> QueryParam "display"    DisplayMode
              :> QueryParam "verbose"     Bool
    -}
              :> Get '[SVG] SVG

-- | TODO
-- Add real text processing
-- Fix Filter parameters
getPhylo :: PhyloId -> GargServer GetPhylo
--getPhylo phId _lId l msb _f _b _l' _ms _x _y _z _ts _s _o _e _d _b' = do
getPhylo phId _lId l msb  = do
  phNode     <- getNodePhylo phId
  let
    level = maybe 2 identity l
    branc = maybe 2 identity msb
    maybePhylo = hyperdataPhylo_data $ _node_hyperdata phNode

  p <- liftIO $ viewPhylo2Svg $ viewPhylo level branc  $ maybe phyloFromQuery identity maybePhylo
  pure (SVG p)
------------------------------------------------------------------------
type PostPhylo =  QueryParam "listId" ListId
               -- :> ReqBody '[JSON] PhyloQueryBuild
               :> (Post '[JSON] NodeId)

postPhylo :: CorpusId -> UserId -> GargServer PostPhylo
postPhylo n userId _lId = do
  -- TODO get Reader settings
  -- s <- ask
  let
    -- _vrs = Just ("1" :: Text)
    -- _sft = Just (Software "Gargantext" "4")
    -- _prm = initPhyloParam vrs sft (Just q)
  phy  <- flowPhylo n
  pId <- insertNodes [nodePhyloW (Just "Phylo") (Just $ HyperdataPhylo Nothing (Just phy)) n userId]
  pure $ NodeId (fromIntegral pId)

------------------------------------------------------------------------
-- | DELETE Phylo == delete a node
------------------------------------------------------------------------
------------------------------------------------------------------------
{-
type PutPhylo = (Put '[JSON] Phylo  )
--putPhylo :: PhyloId -> Maybe ListId -> PhyloQueryBuild -> Phylo
putPhylo :: PhyloId -> GargServer PutPhylo
putPhylo = undefined
-}


-- | Instances
instance Arbitrary PhyloView
  where
    arbitrary = elements [phyloView]

-- | TODO add phyloGroup ex
instance Arbitrary PhyloGroup
  where
    arbitrary = elements []

instance Arbitrary Phylo
  where
    arbitrary = elements [phylo]

instance ToSchema Cluster
instance ToSchema EdgeType
instance ToSchema Filiation
instance ToSchema Filter
instance ToSchema FisParams
instance ToSchema HammingParams
instance ToSchema LouvainParams
instance ToSchema Metric
instance ToSchema Order
instance ToSchema Phylo
instance ToSchema PhyloFis
instance ToSchema PhyloBranch
instance ToSchema PhyloEdge
instance ToSchema PhyloGroup
instance ToSchema PhyloLevel
instance ToSchema PhyloNode
instance ToSchema PhyloParam
instance ToSchema PhyloFoundations
instance ToSchema PhyloPeriod
instance ToSchema PhyloQueryBuild
instance ToSchema PhyloView
instance ToSchema RCParams
instance ToSchema LBParams
instance ToSchema SBParams
instance ToSchema Software
instance ToSchema WLJParams


instance ToParamSchema Order
instance FromHttpApiData Order
  where
    parseUrlPiece = readTextData


instance ToParamSchema Metric
instance FromHttpApiData [Metric]
  where
    parseUrlPiece = readTextData
instance FromHttpApiData Metric
  where
    parseUrlPiece = readTextData


instance ToParamSchema   DisplayMode
instance FromHttpApiData DisplayMode
  where
    parseUrlPiece = readTextData


instance ToParamSchema   ExportMode
instance FromHttpApiData ExportMode
  where
    parseUrlPiece = readTextData    


instance FromHttpApiData Sort
  where
    parseUrlPiece = readTextData
instance ToParamSchema Sort


instance ToSchema Proximity
  where
    declareNamedSchema = genericDeclareNamedSchemaUnrestricted
                       $ swaggerOptions ""


instance FromHttpApiData [Tagger]
  where
    parseUrlPiece = readTextData
instance FromHttpApiData Tagger
  where
    parseUrlPiece = readTextData
instance ToParamSchema   Tagger

instance FromHttpApiData Filiation
  where
    parseUrlPiece = readTextData
instance ToParamSchema   Filiation


