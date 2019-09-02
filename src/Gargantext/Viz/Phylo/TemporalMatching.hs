{-|
Module      : Gargantext.Viz.Phylo.TemporalMatching
Description : Module dedicated to the adaptative temporal matching of a Phylo.
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX
-}

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gargantext.Viz.Phylo.TemporalMatching where

import Data.List (concat, splitAt, tail, sortOn, (++), intersect, null, inits, find, groupBy, scanl, nub, union)
import Data.Map  (Map, fromList, fromListWith, filterWithKey, elems, restrictKeys, unionWith, intersectionWith)

import Gargantext.Prelude
import Gargantext.Viz.AdaptativePhylo
import Gargantext.Viz.Phylo.PhyloTools
import Gargantext.Viz.Phylo.SynchronicClustering

import Control.Lens hiding (Level)

import qualified Data.Set as Set

-------------------
-- | Proximity | --
-------------------


-- | Process the inverse sumLog
sumInvLog :: Double -> [Double] -> Double
sumInvLog s l = foldl (\mem x -> mem + (1 / log (s + x))) 0 l


-- | Process the sumLog
sumLog :: Double -> [Double] -> Double
sumLog s l = foldl (\mem x -> mem + log (s + x)) 0 l  


-- | To compute a jaccard similarity between two lists
jaccard :: [Int] -> [Int] -> Double
jaccard inter' union' = ((fromIntegral . length) $ inter') / ((fromIntegral . length) $ union')


-- | To process a WeighedLogJaccard distance between to coocurency matrix
weightedLogJaccard :: Double -> Double -> Cooc -> Cooc -> [Int] -> [Int] -> Double
weightedLogJaccard sens docs cooc cooc' ngrams ngrams'
  | null ngramsInter           = 0
  | ngramsInter == ngramsUnion = 1
  | sens == 0    = jaccard ngramsInter ngramsUnion
  | sens > 0     = (sumInvLog sens coocInter) / (sumInvLog sens coocUnion)
  | otherwise    = (sumLog sens coocInter) / (sumLog sens coocUnion)
  where
    --------------------------------------
    ngramsInter :: [Int] 
    ngramsInter = intersect ngrams ngrams'   
    --------------------------------------
    ngramsUnion :: [Int] 
    ngramsUnion = union ngrams ngrams'
    --------------------------------------
    coocInter :: [Double]
    coocInter = elems $ map (/docs) $ intersectionWith (+) cooc cooc'      
    --------------------------------------
    coocUnion :: [Double]
    coocUnion = elems $ map (/docs) $ unionWith (+) cooc cooc'
    --------------------------------------


-- | To choose a proximity function
pickProximity :: Proximity -> Double -> Cooc -> Cooc -> [Int] -> [Int] -> Double
pickProximity proximity docs cooc cooc' ngrams ngrams' = case proximity of
    WeightedLogJaccard sens _ _ -> weightedLogJaccard sens docs cooc cooc' ngrams ngrams'
    Hamming -> undefined


filterProximity :: Proximity -> Double -> Double -> Bool
filterProximity proximity thr local = 
    case proximity of
        WeightedLogJaccard _ _ _ -> local >= thr
        Hamming -> undefined


-- | To process the proximity between a current group and a pair of targets group
toProximity :: Map Date Double -> Proximity -> PhyloGroup -> PhyloGroup -> PhyloGroup -> Double
toProximity docs proximity group target target' = 
    let docs'  = sum $ elems docs
        cooc   = if target == target'
                 then (target ^. phylo_groupCooc)
                 else sumCooc (target ^. phylo_groupCooc) (target' ^. phylo_groupCooc)
        ngrams = if target == target'
                 then (target ^. phylo_groupNgrams)
                 else union (target ^. phylo_groupNgrams) (target' ^. phylo_groupNgrams)
    in pickProximity proximity docs' (group ^. phylo_groupCooc) cooc (group ^. phylo_groupNgrams) ngrams 


------------------------
-- | Local Matching | --
------------------------


-- | Find pairs of valuable candidates to be matched
makePairs :: [PhyloGroup] -> [PhyloPeriodId] -> [(PhyloGroup,PhyloGroup)]
makePairs candidates periods = case null periods of
    True  -> []
          -- | at least on of the pair candidates should be from the last added period
    False -> filter (\(cdt,cdt') -> (inLastPeriod cdt periods)
                                 || (inLastPeriod cdt' periods))
           $ listToKeys candidates
    where 
        inLastPeriod :: PhyloGroup -> [PhyloPeriodId] -> Bool
        inLastPeriod g prds = (g ^. phylo_groupPeriod) == (last' "makePairs" prds)


phyloGroupMatching :: [[PhyloGroup]] -> Filiation -> Proximity -> Map Date Double -> Double-> PhyloGroup -> PhyloGroup
phyloGroupMatching candidates fil proxi docs thr group = case pointers of
    Nothing  -> addPointers group fil TemporalPointer []
    Just pts -> addPointers group fil TemporalPointer
              $ head' "phyloGroupMatching"
              -- | Keep only the best set of pointers grouped by proximity
              $ groupBy (\pt pt' -> snd pt == snd pt')
              $ reverse $ sortOn snd pts
              -- | Find the first time frame where at leats one pointer satisfies the proximity threshold
    where 
        pointers :: Maybe [Pointer]
        pointers = find (not . null)
                 -- | for each time frame, process the proximity on relevant pairs of targeted groups
                 $ scanl (\acc groups ->
                            let periods = nub $ map (\g' -> g' ^. phylo_groupPeriod) $ concat groups
                                pairs = makePairs (concat groups) periods
                            in  acc ++ ( filter (\(_,proximity) -> filterProximity proxi thr proximity)
                                       $ concat
                                       $ map (\(c,c') ->
                                                -- | process the proximity between the current group and a pair of candidates 
                                                let proximity = toProximity (filterDocs docs periods) proxi group c c'
                                                in if (c == c')
                                                   then [(getGroupId c,proximity)]
                                                   else [(getGroupId c,proximity),(getGroupId c',proximity)] ) pairs)
                         ) []
                 -- | groups from [[1900],[1900,1901],[1900,1901,1902],...]
                 $ inits candidates
        --------------------------------------                 
        filterDocs :: Map Date Double -> [PhyloPeriodId] -> Map Date Double
        filterDocs d pds = restrictKeys d $ periodsToYears pds


-----------------------------
-- | Matching Processing | --
-----------------------------


getNextPeriods :: Filiation -> Int -> PhyloPeriodId -> [PhyloPeriodId] -> [PhyloPeriodId]
getNextPeriods fil max' pId pIds = 
    case fil of 
        ToChilds  -> take max' $ (tail . snd) $ splitAt (elemIndex' pId pIds) pIds
        ToParents -> take max' $ (reverse . fst) $ splitAt (elemIndex' pId pIds) pIds


getCandidates :: Filiation -> PhyloGroup -> [PhyloPeriodId] -> [PhyloGroup] -> [[PhyloGroup]]
getCandidates fil g pIds targets = 
    case fil of
        ToChilds  -> targets'
        ToParents -> reverse targets'
    where
        targets' :: [[PhyloGroup]]
        targets' = map (\groups' -> filter (\g' -> (not . null) $ intersect (g ^. phylo_groupNgrams) (g' ^. phylo_groupNgrams)) groups') $ elems
                 $ filterWithKey (\k _ -> elem k pIds) 
                 $ fromListWith (++)
                 $ sortOn (fst . fst)
                 $ map (\g' -> (g' ^. phylo_groupPeriod,[g'])) targets


processMatching :: Int -> [PhyloPeriodId] -> Proximity -> Double -> Map Date Double -> [PhyloGroup] -> [PhyloGroup]
processMatching max' periods proximity thr docs groups =
    map (\group -> 
            let childs  = getCandidates ToChilds  group
                                        (getNextPeriods ToChilds  max' (group ^. phylo_groupPeriod) periods) groups
                parents = getCandidates ToParents group
                                        (getNextPeriods ToParents max' (group ^. phylo_groupPeriod) periods) groups
            in phyloGroupMatching parents ToParents proximity docs thr
             $ phyloGroupMatching childs  ToChilds  proximity docs thr group
        ) groups


-----------------------------
-- | Adaptative Matching | --
-----------------------------


toPhyloQuality :: [[PhyloGroup]] -> Double
toPhyloQuality _ = undefined


groupsToBranches :: Map PhyloGroupId PhyloGroup -> [[PhyloGroup]]
groupsToBranches groups =
    -- | run the related component algorithm
    let graph = zip [1..]
              $ relatedComponents
              $ map (\group -> [getGroupId group] 
                            ++ (map fst $ group ^. phylo_groupPeriodParents)
                            ++ (map fst $ group ^. phylo_groupPeriodChilds) ) $ elems groups
    -- | update each group's branch id
    in map (\(bId,ids) ->
                map (\group -> group & phylo_groupBranchId %~ (\(lvl,lst) -> (lvl,lst ++ [bId])))
                $ elems $ restrictKeys groups (Set.fromList ids)
           ) graph


recursiveMatching :: Proximity -> Double -> Int -> [PhyloPeriodId] -> Map Date Double -> Double -> [PhyloGroup] -> [PhyloGroup]
recursiveMatching proximity thr max' periods docs quality groups   =
    case quality < quality' of
                -- | success : we localy improve the quality of the branch, let's go deeper
        True  -> concat 
               $ map (\branch ->
                        recursiveMatching proximity (thr + (getThresholdStep proximity)) max' periods docs quality' branch
                     ) branches
                -- | failure : last step was the local maximum, let's validate it
        False -> groups
    where
        -- | 3) process a quality score on the local set of branches
        quality' :: Double
        quality' = toPhyloQuality branches
        -- | 2) group the new groups into branches 
        branches :: [[PhyloGroup]]
        branches = groupsToBranches $ fromList $ map (\group -> (getGroupId group, group)) groups'
        -- | 1) process a temporal matching for each group
        groups' :: [PhyloGroup]
        groups' = processMatching max' periods proximity thr docs groups


temporalMatching :: Phylo -> Phylo
temporalMatching phylo = updatePhyloGroups 1 branches phylo
    where
        -- | 2) run the recursive matching to find the best repartition among branches
        branches :: Map PhyloGroupId PhyloGroup
        branches = fromList 
                 $ map (\g -> (getGroupId g, g))
                 $ recursiveMatching (phyloProximity $ getConfig phylo) 
                                     (getThresholdInit $ phyloProximity $ getConfig phylo) 
                                     (getTimeFrame $ timeUnit $ getConfig phylo)
                                     (getPeriodIds phylo)
                                     (phylo ^. phylo_timeDocs) (toPhyloQuality [groups']) groups'
        -- | 1) for each group process an initial temporal Matching
        groups' :: [PhyloGroup]
        groups' = processMatching (getTimeFrame $ timeUnit $ getConfig phylo) (getPeriodIds phylo) 
                                  (phyloProximity $ getConfig phylo) (getThresholdInit $ phyloProximity $ getConfig phylo)
                                  (phylo ^. phylo_timeDocs) (getGroupsFromLevel 1 phylo)
