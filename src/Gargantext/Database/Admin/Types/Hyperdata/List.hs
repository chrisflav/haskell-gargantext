{-|
Module      : Gargantext.Database.Admin.Types.Hyperdata.List
Description :
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE TemplateHaskell            #-}

module Gargantext.Database.Admin.Types.Hyperdata.List
  where

import Data.Vector (Vector)
--import qualified Data.Vector as V
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Control.Applicative

import Gargantext.Prelude
import Gargantext.Core.Viz.Types (Histo(..))
import Gargantext.API.Ngrams.NgramsTree (NgramsTree)
import Gargantext.API.Ngrams.Types (TabType)
import Gargantext.Database.Admin.Types.Hyperdata.Prelude
import Gargantext.Database.Admin.Types.Metrics (ChartMetrics(..), Metrics)

------------------------------------------------------------------------
data HyperdataList =
  HyperdataList { _hl_chart   :: !(HashMap TabType (ChartMetrics Histo))
                , _hl_list    :: !(Maybe Text)
                , _hl_pie     :: !(HashMap TabType (ChartMetrics Histo))
                , _hl_scatter :: !(HashMap TabType Metrics)
                , _hl_tree    :: !(HashMap TabType (ChartMetrics (Vector NgramsTree)))
                } deriving (Show, Generic)
  -- HyperdataList { _hl_chart   :: !(Maybe (ChartMetrics Histo))
  --               , _hl_list    :: !(Maybe Text)
  --               , _hl_pie     :: !(Maybe (ChartMetrics Histo))
  --               , _hl_scatter :: !(Maybe Metrics)
  --               , _hl_tree    :: !(Maybe (ChartMetrics [NgramsTree]))
  --               } deriving (Show, Generic)

defaultHyperdataList :: HyperdataList
defaultHyperdataList =
  HyperdataList { _hl_chart   = HM.empty
                , _hl_list    = Nothing
                , _hl_pie     = HM.empty
                , _hl_scatter = HM.empty
                , _hl_tree    = HM.empty
                }

------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------
instance Hyperdata HyperdataList

$(makeLenses ''HyperdataList)
$(deriveJSON (unPrefix "_hl_") ''HyperdataList)


------------------------------------------------------------------------
data HyperdataListCooc =
  HyperdataListCooc { _hlc_preferences :: !Text }
  deriving (Generic)

defaultHyperdataListCooc :: HyperdataListCooc
defaultHyperdataListCooc = HyperdataListCooc ""


instance Hyperdata HyperdataListCooc
$(makeLenses ''HyperdataListCooc)
$(deriveJSON (unPrefix "_hlc_") ''HyperdataListCooc)





instance Arbitrary HyperdataList where
  arbitrary = pure defaultHyperdataList
instance Arbitrary HyperdataListCooc where
  arbitrary = pure defaultHyperdataListCooc


instance FromField HyperdataList
  where
    fromField = fromField'

instance FromField HyperdataListCooc
  where
    fromField = fromField'

instance DefaultFromField SqlJsonb HyperdataList
  where
    defaultFromField = fromPGSFromField
instance DefaultFromField SqlJsonb HyperdataListCooc
  where
    defaultFromField = fromPGSFromField


instance ToSchema HyperdataList where
  declareNamedSchema proxy =
    genericDeclareNamedSchema (unPrefixSwagger "_hl_") proxy
    & mapped.schema.description ?~ "List Hyperdata"
    & mapped.schema.example ?~ toJSON defaultHyperdataList
instance ToSchema HyperdataListCooc where
  declareNamedSchema proxy =
    genericDeclareNamedSchema (unPrefixSwagger "_hlc_") proxy
    & mapped.schema.description ?~ "List Cooc Hyperdata"
    & mapped.schema.example ?~ toJSON defaultHyperdataListCooc

