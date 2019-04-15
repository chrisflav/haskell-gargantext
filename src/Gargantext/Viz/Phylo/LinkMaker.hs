{-|
Module      : Gargantext.Viz.Phylo.Tools
Description : Phylomemy Tools to build/manage it
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX


-}

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}

module Gargantext.Viz.Phylo.LinkMaker
  where

import Control.Lens                 hiding (both, Level)
import Data.List                    ((++), nub, sortOn, null, tail, splitAt, elem)
import Data.Tuple.Extra
import Gargantext.Prelude
import Gargantext.Viz.Phylo
import Gargantext.Viz.Phylo.Tools
import Gargantext.Viz.Phylo.Metrics.Proximity
import qualified Data.List  as List
import qualified Data.Maybe as Maybe


------------------------------------------------------------------------
-- | Make links from Level to Level


-- | To choose a LevelLink strategy based an a given Level
shouldLink :: (Level,Level) -> PhyloGroup -> PhyloGroup -> Bool
shouldLink (lvl,_lvl) g g'
  | lvl <= 1  = doesContainsOrd (getGroupNgrams g) (getGroupNgrams g')
  | lvl >  1  = elem (getGroupId g) (getGroupLevelChildsId g')
  | otherwise = panic ("[ERR][Viz.Phylo.LinkMaker.shouldLink] Level not defined")


-- | To set the LevelLinks between a given PhyloGroup and a list of childs/parents PhyloGroups
linkGroupToGroups :: (Level,Level) -> PhyloGroup -> [PhyloGroup] -> PhyloGroup
linkGroupToGroups (lvl,lvl') current targets
  | lvl < lvl' = setLevelParents current
  | lvl > lvl' = setLevelChilds current
  | otherwise = current
  where
    --------------------------------------
    setLevelChilds :: PhyloGroup -> PhyloGroup
    setLevelChilds =  over (phylo_groupLevelChilds) addPointers
    --------------------------------------
    setLevelParents :: PhyloGroup -> PhyloGroup
    setLevelParents =  over (phylo_groupLevelParents) addPointers
    --------------------------------------
    addPointers :: [Pointer] -> [Pointer]
    addPointers lp = lp ++ Maybe.mapMaybe (\target ->
                                            if shouldLink (lvl,lvl') current target
                                            then Just ((getGroupId target),1)
                                            else Nothing) targets
    --------------------------------------


-- | To set the LevelLinks between two lists of PhyloGroups
linkGroupsByLevel :: (Level,Level) -> Phylo -> [PhyloGroup] -> [PhyloGroup]
linkGroupsByLevel (lvl,lvl') p groups  = map (\group ->
                                              if getGroupLevel group == lvl
                                              then linkGroupToGroups (lvl,lvl') group (getGroupsWithFilters lvl' (getGroupPeriod group) p)
                                              else group) groups


-- | To set the LevelLink of all the PhyloGroups of a Phylo
setLevelLinks :: (Level,Level) -> Phylo -> Phylo
setLevelLinks (lvl,lvl') p = alterPhyloGroups (linkGroupsByLevel (lvl,lvl') p) p


------------------------------------------------------------------------
-- | Make links from Period to Period


-- | To apply the corresponding proximity function based on a given Proximity
applyProximity :: Proximity -> PhyloGroup -> PhyloGroup -> (PhyloGroupId, Double)
applyProximity prox g1 g2 = case prox of
  WeightedLogJaccard (WLJParams _ s) -> ((getGroupId g2),weightedLogJaccard s (getGroupCooc g1) (unifySharedKeys (getGroupCooc g2) (getGroupCooc g1)))
  Hamming (HammingParams _)          -> ((getGroupId g2),hamming (getGroupCooc g1) (unifySharedKeys (getGroupCooc g2) (getGroupCooc g1)))
  _                                  -> panic ("[ERR][Viz.Phylo.Example.applyProximity] Proximity function not defined")


-- | To get the next or previous PhyloPeriod based on a given PhyloPeriodId
getNextPeriods :: Filiation -> PhyloPeriodId -> [PhyloPeriodId] -> [PhyloPeriodId]
getNextPeriods to' id l = case to' of
    Descendant -> (tail . snd) next
    Ascendant  -> (reverse . fst) next
    _          -> panic ("[ERR][Viz.Phylo.Example.getNextPeriods] Filiation type not defined")
    where
      --------------------------------------
      next :: ([PhyloPeriodId], [PhyloPeriodId])
      next = splitAt idx l
      --------------------------------------
      idx :: Int
      idx = case (List.elemIndex id l) of
        Nothing -> panic ("[ERR][Viz.Phylo.Example.getNextPeriods] PhyloPeriodId not defined")
        Just i  -> i
      --------------------------------------


-- | To find the best set (max = 2) of Childs/Parents candidates based on a given Proximity mesure until a maximum depth (max = Period + 5 units )
findBestCandidates :: Filiation -> Int -> Int -> Proximity -> PhyloGroup -> Phylo -> [(PhyloGroupId, Double)]
findBestCandidates to' depth max' prox group p
  | depth > max' || null next = []
  | (not . null) best = take 2 best
  | otherwise = findBestCandidates to' (depth + 1) max' prox group p
  where
    --------------------------------------
    next :: [PhyloPeriodId]
    next = getNextPeriods to' (getGroupPeriod group) (getPhyloPeriods p)
    --------------------------------------
    candidates :: [PhyloGroup]
    candidates = getGroupsWithFilters (getGroupLevel group) (head' "findBestCandidates" next) p
    --------------------------------------
    scores :: [(PhyloGroupId, Double)]
    scores = map (\group' -> applyProximity prox group group') candidates
    --------------------------------------
    best :: [(PhyloGroupId, Double)]
    best = reverse
         $ sortOn snd
         $ filter (\(_id,score) -> case prox of
            WeightedLogJaccard (WLJParams thr _) -> score >= thr
            Hamming (HammingParams thr)          -> score <= thr
            Filiation                            -> panic "[ERR][Viz.Phylo.LinkMaker.findBestCandidates] Filiation"
            ) scores
    --------------------------------------


-- | To add a new list of Pointers into an existing Childs/Parents list of Pointers
makePair :: Filiation -> PhyloGroup -> [(PhyloGroupId, Double)] -> PhyloGroup
makePair to' group ids = case to' of
    Descendant  -> over (phylo_groupPeriodChilds) addPointers group
    Ascendant   -> over (phylo_groupPeriodParents) addPointers group
    _           -> panic ("[ERR][Viz.Phylo.Example.makePair] Filiation type not defined")
    where
      --------------------------------------
      addPointers :: [Pointer] -> [Pointer]
      addPointers l = nub $ (l ++ ids)
      --------------------------------------


-- | To pair all the Phylogroups of given PhyloLevel to their best Parents or Childs
interTempoMatching :: Filiation -> Level -> Proximity -> Phylo -> Phylo
interTempoMatching to' lvl prox p = alterPhyloGroups
                                    (\groups ->
                                      map (\group ->
                                            if (getGroupLevel group) == lvl
                                            then
                                              let
                                                --------------------------------------
                                                candidates :: [(PhyloGroupId, Double)]
                                                candidates = findBestCandidates to' 1 5 prox group p
                                                --------------------------------------
                                              in
                                                makePair to' group candidates
                                            else
                                              group ) groups) p
