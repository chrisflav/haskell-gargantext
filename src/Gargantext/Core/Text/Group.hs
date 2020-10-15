{-|
Module      : Gargantext.Core.Text.Group
Description : 
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# LANGUAGE TemplateHaskell   #-}

module Gargantext.Core.Text.Group
  where

import Control.Lens (makeLenses, set)
import Data.Set (Set)
import Data.Map (Map)
import Data.Text (Text)
import Gargantext.Core (Lang(..))
import Gargantext.Core.Types (ListType(..))
import Gargantext.Database.Admin.Types.Node (NodeId)
import Gargantext.Core.Text.List.Learn (Model(..))
import Gargantext.Core.Types (MasterCorpusId, UserCorpusId)
import Gargantext.Core.Text.Terms.Mono.Stem (stem)
import Gargantext.Prelude
import qualified Data.Set  as Set
import qualified Data.Map  as Map
import qualified Data.List as List
import qualified Data.Text as Text

data NgramsListBuilder = BuilderStepO { stemSize :: !Int
                                      , stemX    :: !Int
                                      , stopSize :: !StopSize
                                      }
                       | BuilderStep1 { withModel :: !Model }
                       | BuilderStepN { withModel :: !Model }
                       | Tficf { nlb_lang           :: !Lang
                               , nlb_group1         :: !Int
                               , nlb_group2         :: !Int
                               , nlb_stopSize       :: !StopSize
                               , nlb_userCorpusId   :: !UserCorpusId
                               , nlb_masterCorpusId :: !MasterCorpusId
                               }

data StopSize = StopSize {unStopSize :: !Int}

-- | TODO: group with 2 terms only can be
-- discussed. Main purpose of this is offering
-- a first grouping option to user and get some
-- enriched data to better learn and improve that algo

data GroupParams = GroupParams { unGroupParams_lang  :: !Lang
                               , unGroupParams_len   :: !Int
                               , unGroupParams_limit :: !Int
                               , unGroupParams_stopSize :: !StopSize
                               }

ngramsGroup :: GroupParams
            -> Text
            -> Text
ngramsGroup (GroupParams l _m _n _) = Text.intercalate " "
                  . map (stem l)
                  -- . take n
                  . List.sort
                  -- . (List.filter (\t -> Text.length t > m))
                  . Text.splitOn " "
                  . Text.replace "-" " "

------------------------------------------------------------------------------
type Group = Lang -> Int -> Int -> Text -> Text
type Stem  = Text
type Label = Text
data GroupedText score =
  GroupedText { _gt_listType :: !(Maybe ListType)
              , _gt_label    :: !Label
              , _gt_score    :: !score
              , _gt_group    :: !(Set Text)
              , _gt_size     :: !Int
              , _gt_stem     :: !Stem
              , _gt_nodes    :: !(Set NodeId)
              }
instance Show score => Show (GroupedText score) where
  show (GroupedText _ l s _ _ _ _) = show l <> ":" <> show s

instance (Eq a) => Eq (GroupedText a) where
  (==) (GroupedText _ _ score1 _ _ _ _)
       (GroupedText _ _ score2 _ _ _ _) = (==) score1 score2

instance (Eq a, Ord a) => Ord (GroupedText a) where
  compare (GroupedText _ _ score1 _ _ _ _)
          (GroupedText _ _ score2 _ _ _ _) = compare score1 score2

-- Lenses Instances
makeLenses 'GroupedText

------------------------------------------------------------------------------
addListType :: Map Text ListType -> GroupedText a -> GroupedText a
addListType m g = set gt_listType lt g
  where
    lt = hasListType m g

hasListType :: Map Text ListType -> GroupedText a -> Maybe ListType
hasListType m (GroupedText _ label _ g _ _ _) =
  List.foldl' (<>) Nothing
  $ map (\t -> Map.lookup t m)
  $ Set.toList
  $ Set.insert label g





