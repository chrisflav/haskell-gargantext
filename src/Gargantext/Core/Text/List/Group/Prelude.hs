{-|
Module      : Gargantext.Core.Text.List.Group.Prelude
Description :
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# LANGUAGE TemplateHaskell        #-}

module Gargantext.Core.Text.List.Group.Prelude
  where

import Control.Lens (makeLenses, view, set)
import Data.Monoid
import Data.Semigroup
import Data.Set (Set)
import Data.Text (Text)
import Data.Map (Map)
import Gargantext.Core.Types (ListType(..))
import Gargantext.Database.Admin.Types.Node (NodeId)
import Gargantext.Prelude
import qualified Data.Set as Set
import qualified Data.Map as Map

------------------------------------------------------------------------
-- | Group With Scores Main Types
-- Tree of GroupedTextScores
-- Target : type FlowCont Text GroupedTextScores'

data GroupedTreeScores score =
  GroupedTreeScores { _gts'_listType :: !(Maybe ListType)
                    , _gts'_children :: !(Map Text (GroupedTreeScores score))
                    , _gts'_score    :: score
                    } deriving (Show, Ord, Eq)

instance (Semigroup a, Ord a) => Semigroup (GroupedTreeScores a) where
  (<>) (GroupedTreeScores  l1 s1 c1)
       (GroupedTreeScores  l2 s2 c2)
      = GroupedTreeScores (l1 <> l2)
                          (s1 <> s2)
                          (c1 <> c2)

instance (Ord score, Monoid score)
  => Monoid (GroupedTreeScores score) where
    mempty = GroupedTreeScores Nothing Map.empty mempty

makeLenses 'GroupedTreeScores

---------------------------------------------
class ViewListType a where
  viewListType :: a -> Maybe ListType

class SetListType a where
  setListType :: Maybe ListType -> a -> a

class ViewScore a b where
  viewScore :: a -> b


instance ViewListType (GroupedTreeScores a) where
  viewListType = view gts'_listType

instance SetListType (GroupedTreeScores a) where
  setListType = set gts'_listType

{-
instance ViewScore (GroupedTreeScores a) b where
  viewScore = view gts'_score
-}


-- 8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--
-- TODO to remove below
data GroupedWithListScores =
  GroupedWithListScores { _gwls_listType :: !(Maybe ListType)
                        , _gwls_children :: !(Set Text)
                        } deriving (Show)

instance Semigroup GroupedWithListScores where
  (<>) (GroupedWithListScores c1 l1)
       (GroupedWithListScores c2 l2) =
        GroupedWithListScores (c1 <> c2)
                              (l1 <> l2)

instance Monoid GroupedWithListScores where
  mempty = GroupedWithListScores Nothing Set.empty

makeLenses ''GroupedWithListScores
-- 8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--8<--

------------------------------------------------------------------------
------------------------------------------------------------------------
-- | Group With Stem Main Types
type Stem  = Text
data GroupedText score =
  GroupedText { _gt_listType :: !(Maybe ListType)
              , _gt_label    :: !Text
              , _gt_score    :: !score
              , _gt_children :: !(Set Text)
              , _gt_size     :: !Int
              , _gt_stem     :: !Stem -- needed ?
              , _gt_nodes    :: !(Set NodeId)
              }  deriving (Show, Eq) --}

-- | Lenses Instances
makeLenses 'GroupedText

instance ViewListType (GroupedText a) where
  viewListType = view gt_listType

instance SetListType (GroupedText a) where
  setListType = set gt_listType

{-
instance Show score => Show (GroupedText score) where
  show (GroupedText lt l s _ _ _ _) = show l <> " : " <> show lt <> " : " <> show s
--}

{-
instance (Eq a) => Eq (GroupedText a) where
  (==) (GroupedText _ _ score1 _ _ _ _)
       (GroupedText _ _ score2 _ _ _ _) = (==) score1 score2
-}

instance (Eq a, Ord a) => Ord (GroupedText a) where
  compare (GroupedText _ _ score1 _ _ _ _)
          (GroupedText _ _ score2 _ _ _ _) = compare score1 score2

instance Ord a => Semigroup (GroupedText a) where
  (<>) (GroupedText lt1 label1 score1 group1 s1 stem1 nodes1)
        (GroupedText lt2 label2 score2 group2 s2 stem2 nodes2)
          | score1 >= score2 = GroupedText lt label1 score1 (Set.insert label2 gr) s1 stem1 nodes
          | otherwise        = GroupedText lt label2 score2 (Set.insert label1 gr) s2 stem2 nodes
    where
      lt = lt1 <> lt2
      gr    = Set.union group1 group2
      nodes = Set.union nodes1 nodes2



