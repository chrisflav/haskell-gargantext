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

module Gargantext.Viz.Phylo.Tools
  where

import Control.Lens         hiding (both, Level)
import Data.List            (filter, intersect, (++), sort, null, head, tail, last, tails, delete, nub, concat, union, sortOn)
import Data.Maybe           (mapMaybe)
import Data.Map             (Map, mapKeys, member, elems, adjust, (!))
import Data.Set             (Set)
import Data.Text            (Text, toLower)
import Data.Tuple.Extra
import Data.Vector          (Vector,elemIndex)
import Gargantext.Prelude   hiding (head)
import Gargantext.Viz.Phylo

import qualified Data.List   as List
import qualified Data.Map    as Map
import qualified Data.Set    as Set
import qualified Data.Vector as Vector


------------------------------------------------------------------------
-- | Tools | --


-- | To alter a PhyloGroup matching a given Level
alterGroupWithLevel :: (PhyloGroup -> PhyloGroup) -> Level -> Phylo -> Phylo
alterGroupWithLevel f lvl p = over ( phylo_periods
                                   .  traverse
                                   . phylo_periodLevels
                                   .  traverse
                                   . phylo_levelGroups
                                   .  traverse
                                   ) (\g -> if getGroupLevel g == lvl
                                            then f g
                                            else g ) p  


-- | To alter each list of PhyloGroups following a given function
alterPhyloGroups :: ([PhyloGroup] -> [PhyloGroup]) -> Phylo -> Phylo
alterPhyloGroups f p = over ( phylo_periods
                            .  traverse
                            . phylo_periodLevels
                            .  traverse
                            . phylo_levelGroups
                            ) f p   


-- | To alter each PhyloPeriod of a Phylo following a given function
alterPhyloPeriods :: (PhyloPeriod -> PhyloPeriod) -> Phylo -> Phylo
alterPhyloPeriods f p = over ( phylo_periods
                             .  traverse) f p


-- | To alter a list of PhyloLevels following a given function
alterPhyloLevels :: ([PhyloLevel] -> [PhyloLevel]) -> Phylo -> Phylo
alterPhyloLevels f p = over ( phylo_periods
                            .  traverse
                            . phylo_periodLevels) f p


-- | To append a list of PhyloPeriod to a Phylo
appendToPhyloPeriods :: [PhyloPeriod] -> Phylo -> Phylo
appendToPhyloPeriods l p = over (phylo_periods) (++ l) p


-- | Does a List of Sets contains at least one Set of an other List
doesAnySetContains :: Eq a =>  Set a -> [Set a] -> [Set a] -> Bool
doesAnySetContains h l l' = any (\c -> doesContains (Set.toList c) (Set.toList h)) (l' ++ l)


-- | Does a list of A contains an other list of A
doesContains :: Eq a => [a] -> [a] -> Bool
doesContains l l'
  | null l'               = True
  | length l' > length l  = False
  | elem (head l') l      = doesContains l (tail l')
  | otherwise             = False


-- | Does a list of ordered A contains an other list of ordered A
doesContainsOrd :: Eq a => Ord a => [a] -> [a] -> Bool
doesContainsOrd l l'
  | null l'          = False
  | last l < head l' = False
  | head l' `elem` l = True
  | otherwise        = doesContainsOrd l (tail l')


 -- | To filter the PhyloGroup of a Phylo according to a function and a value
filterGroups :: Eq a => (PhyloGroup -> a) -> a -> [PhyloGroup] -> [PhyloGroup]
filterGroups f x l = filter (\g -> (f g) == x) l


-- | To filter nested Sets of a
filterNestedSets :: Eq a => Set a -> [Set a] -> [Set a] -> [Set a]
filterNestedSets h l l'
  | null l                 = if doesAnySetContains h l l'
                             then l'
                             else h : l'
  | doesAnySetContains h l l' = filterNestedSets (head l) (tail l) l'
  | otherwise              = filterNestedSets (head l) (tail l) (h : l')


-- | To filter some GroupEdges with a given threshold
filterGroupEdges :: Double -> GroupEdges -> GroupEdges
filterGroupEdges thr edges = filter (\((s,t),w) -> w > thr) edges 


-- | To get the PhyloBranchId of a PhyloBranch
getBranchId :: PhyloBranch -> PhyloBranchId
getBranchId b = b ^. phylo_branchId


-- | To get a list of PhyloBranchIds given a Level in a Phylo
getBranchIdsWith :: Level -> Phylo -> [PhyloBranchId]
getBranchIdsWith lvl p = sortOn snd
                       $ mapMaybe getGroupBranchId
                       $ getGroupsWithLevel lvl p


-- | To get the Meta value of a PhyloBranch 
getBranchMeta :: Text -> PhyloBranch -> Double 
getBranchMeta k b = (b ^. phylo_branchMeta) ! k


-- | To get the Name of a Clustering Methods
getClusterName :: Clustering -> ClusteringName
getClusterName c = _clustering_name c


-- | To get the params of a Clustering Methods
getClusterParam :: Clustering -> Text -> Double
getClusterParam c k = if (member k $ _clustering_params c)
                      then (_clustering_params c) Map.! k
                      else panic "[ERR][Viz.Phylo.Tools.getClusterParam] the key is not in params"


-- | To get the boolean params of a Clustering Methods
getClusterParamBool :: Clustering -> Text -> Bool
getClusterParamBool c k = if (member k $ _clustering_paramsBool c)
                      then (_clustering_paramsBool c) Map.! k
                      else panic "[ERR][Viz.Phylo.Tools.getClusterParamBool] the key is not in paramsBool"


-- | To get the first clustering method to apply to get the level 1 of a Phylo
getFstCluster :: PhyloQuery -> Clustering
getFstCluster q = q ^. phyloQuery_fstCluster


-- | To get the foundations of a Phylo
getFoundations :: Phylo -> Vector Ngrams
getFoundations = _phylo_foundations


-- | To get the Index of a Ngrams in the Foundations of a Phylo
getIdxInFoundations :: Ngrams -> Phylo -> Int
getIdxInFoundations n p = case (elemIndex n (getFoundations p)) of
    Nothing  -> panic "[ERR][Viz.Phylo.Tools.getFoundationIdx] Ngrams not in Foundations"
    Just idx -> idx


-- | To maybe get the PhyloBranchId of a PhyloGroup
getGroupBranchId :: PhyloGroup -> Maybe PhyloBranchId
getGroupBranchId = _phylo_groupBranchId 


-- | To get the PhyloGroups Childs of a PhyloGroup
getGroupChilds :: PhyloGroup -> Phylo -> [PhyloGroup]
getGroupChilds g p = getGroupsFromIds (getGroupPeriodChildsId g) p


-- | To get the id of a PhyloGroup
getGroupId :: PhyloGroup -> PhyloGroupId
getGroupId = _phylo_groupId


-- | To get the Cooc Matrix of a PhyloGroup
getGroupCooc :: PhyloGroup -> Map (Int,Int) Double
getGroupCooc = _phylo_groupCooc


-- | To get the level out of the id of a PhyloGroup
getGroupLevel :: PhyloGroup -> Int
getGroupLevel = snd . fst . getGroupId


-- | To get the level child pointers of a PhyloGroup
getGroupLevelChilds :: PhyloGroup -> [Pointer]
getGroupLevelChilds = _phylo_groupLevelChilds


-- | To get the PhyloGroups Level Childs Ids of a PhyloGroup
getGroupLevelChildsId :: PhyloGroup -> [PhyloGroupId]
getGroupLevelChildsId g = map fst $ getGroupLevelChilds g


-- | To get the level parent pointers of a PhyloGroup
getGroupLevelParents :: PhyloGroup -> [Pointer]
getGroupLevelParents = _phylo_groupLevelParents


-- | To get the PhyloGroups Level Parents Ids of a PhyloGroup
getGroupLevelParentsId :: PhyloGroup -> [PhyloGroupId]
getGroupLevelParentsId g = map fst $ getGroupLevelParents g


-- | To get the Ngrams of a PhyloGroup
getGroupNgrams :: PhyloGroup -> [Int]
getGroupNgrams =  _phylo_groupNgrams


-- | To get the list of pairs (Childs & Parents) of a PhyloGroup
getGroupPairs :: PhyloGroup -> Phylo -> [PhyloGroup]
getGroupPairs g p = (getGroupChilds g p) ++ (getGroupParents g p)


-- | To get the PhyloGroups Parents of a PhyloGroup
getGroupParents :: PhyloGroup -> Phylo -> [PhyloGroup]
getGroupParents g p = getGroupsFromIds (getGroupPeriodParentsId g) p


-- | To get the period out of the id of a PhyloGroup
getGroupPeriod :: PhyloGroup -> (Date,Date)
getGroupPeriod = fst . fst . getGroupId


-- | To get the period child pointers of a PhyloGroup
getGroupPeriodChilds :: PhyloGroup -> [Pointer]
getGroupPeriodChilds = _phylo_groupPeriodChilds


-- | To get the PhyloGroups Period Parents Ids of a PhyloGroup
getGroupPeriodChildsId :: PhyloGroup -> [PhyloGroupId]
getGroupPeriodChildsId g = map fst $ getGroupPeriodChilds g


-- | To get the period parent pointers of a PhyloGroup
getGroupPeriodParents :: PhyloGroup -> [Pointer]
getGroupPeriodParents = _phylo_groupPeriodParents


-- | To get the PhyloGroups Period Parents Ids of a PhyloGroup
getGroupPeriodParentsId :: PhyloGroup -> [PhyloGroupId]
getGroupPeriodParentsId g = map fst $ getGroupPeriodParents g


-- | To get all the PhyloGroup of a Phylo
getGroups :: Phylo -> [PhyloGroup]
getGroups = view ( phylo_periods
                 .  traverse
                 . phylo_periodLevels
                 .  traverse 
                 . phylo_levelGroups
                 )


-- | To get all PhyloGroups matching a list of PhyloGroupIds in a Phylo
getGroupsFromIds :: [PhyloGroupId] -> Phylo -> [PhyloGroup]
getGroupsFromIds ids p = filter (\g -> elem (getGroupId g) ids) $ getGroups p


-- | To get the corresponding list of PhyloGroups from a list of PhyloNodes
getGroupsFromNodes :: [PhyloNode] -> Phylo -> [PhyloGroup]
getGroupsFromNodes ns p = getGroupsFromIds (map getNodeId ns) p 


-- | To get all the PhyloGroup of a Phylo with a given level and period
getGroupsWithFilters :: Int -> (Date,Date) -> Phylo -> [PhyloGroup]
getGroupsWithFilters lvl prd p = (getGroupsWithLevel  lvl p)
                                 `intersect`
                                 (getGroupsWithPeriod prd p)


-- | To get all the PhyloGroup of a Phylo with a given Level
getGroupsWithLevel :: Int -> Phylo -> [PhyloGroup]
getGroupsWithLevel lvl p = filterGroups getGroupLevel lvl (getGroups p)


-- | To get all the PhyloGroup of a Phylo with a given Period
getGroupsWithPeriod :: (Date,Date) -> Phylo -> [PhyloGroup]
getGroupsWithPeriod prd p = filterGroups getGroupPeriod prd (getGroups p)
              

-- | To get the good pair of keys (x,y) or (y,x) in a given Map (a,b) c
getKeyPair :: (Int,Int) -> Map (Int,Int) a -> (Int,Int)
getKeyPair (x,y) m = case findPair (x,y) m of
                      Nothing -> panic "[ERR][Viz.Phylo.Example.getKeyPair] Nothing"
                      Just i  -> i
                     where
                      --------------------------------------
                      findPair :: (Int,Int) -> Map (Int,Int) a -> Maybe (Int,Int)
                      findPair (x,y) m
                        | member (x,y) m = Just (x,y)
                        | member (y,x) m = Just (y,x)
                        | otherwise      = Nothing
                      --------------------------------------


-- | To get the last computed Level in a Phylo
getLastLevel :: Phylo -> Level 
getLastLevel p = (last . sort) 
               $ map (snd . getPhyloLevelId) 
               $ view ( phylo_periods
                      .  traverse
                      . phylo_periodLevels ) p



-- | To get the neighbours (directed/undirected) of a PhyloGroup from a list of GroupEdges 
getNeighbours :: Bool -> PhyloGroup -> GroupEdges -> [PhyloGroup]
getNeighbours directed g e = case directed of 
  True  -> map (\((s,t),w) -> t) 
             $ filter (\((s,t),w) -> s == g) e 
  False -> map (\((s,t),w) -> head $ delete g $ nub [s,t,g]) 
             $ filter (\((s,t),w) -> s == g || t == g) e


-- | To get the PhyloBranchId of PhyloNode if it exists
getNodeBranchId :: PhyloNode -> PhyloBranchId
getNodeBranchId n = case n ^. phylo_nodeBranchId of
                     Nothing -> panic "[ERR][Viz.Phylo.Tools.getNodeBranchId] branchId not found"
                     Just i  -> i 


-- | To get the PhyloGroupId of a PhyloNode
getNodeId :: PhyloNode -> PhyloGroupId
getNodeId n = n ^. phylo_nodeId


-- | To get the Level of a PhyloNode
getNodeLevel :: PhyloNode -> Level
getNodeLevel n = (snd . fst) $ getNodeId n


-- | To get the Parent Node of a PhyloNode in a PhyloView
getNodeParent :: PhyloNode -> PhyloView -> PhyloNode
getNodeParent n v = head 
                  $ filter (\n' -> getNodeId n' == getNodeParentId n)
                  $ v ^. phylo_viewNodes


-- | To get the Parent Node id of a PhyloNode if it exists
getNodeParentId :: PhyloNode -> PhyloGroupId
getNodeParentId n = case n ^. phylo_nodeParent of
                    Nothing -> panic "[ERR][Viz.Phylo.Tools.getNodeParentId] node parent not found"
                    Just id -> id


-- | To get a list of PhyloNodes grouped by PhyloBranch in a PhyloView
getNodesByBranches :: PhyloView -> [(PhyloBranchId,[PhyloNode])]
getNodesByBranches v = zip bIds $ map (\id -> filter (\n -> (getNodeBranchId n) == id) 
                                            $ getNodesInBranches v ) bIds
  where
    -------------------------------------- 
    bIds :: [PhyloBranchId] 
    bIds = getViewBranchIds v 
    --------------------------------------


-- | To get a list of PhyloNodes owned by any PhyloBranches in a PhyloView
getNodesInBranches :: PhyloView -> [PhyloNode]
getNodesInBranches v = filter (\n -> isJust $ n ^. phylo_nodeBranchId)
                     $ v ^. phylo_viewNodes


-- | To get the cluster methods to apply to the Nths levels of a Phylo
getNthCluster :: PhyloQuery -> Clustering
getNthCluster q = q ^. phyloQuery_nthCluster


-- | To get the Sup Level of a reconstruction of a Phylo from a PhyloQuery
getNthLevel :: PhyloQuery -> Level
getNthLevel q = q ^. phyloQuery_nthLevel


-- | To get the PhylolevelId of a given PhyloLevel
getPhyloLevelId :: PhyloLevel -> PhyloLevelId
getPhyloLevelId = _phylo_levelId


-- | To get all the Phylolevels of a given PhyloPeriod
getPhyloLevels :: PhyloPeriod -> [PhyloLevel]
getPhyloLevels = view (phylo_periodLevels)


-- | To get all the PhyloPeriodIds of a Phylo
getPhyloPeriods :: Phylo -> [PhyloPeriodId]
getPhyloPeriods p = map _phylo_periodId 
                  $ view (phylo_periods) p


-- | To get the id of a given PhyloPeriod
getPhyloPeriodId :: PhyloPeriod -> PhyloPeriodId
getPhyloPeriodId prd = _phylo_periodId prd 


-- | To get the sensibility of a Proximity if it exists
getSensibility :: Proximity -> Double
getSensibility prox = if (member "sensibility" $ prox ^. proximity_params)
                      then (prox ^. proximity_params) ! "sensibility"
                      else panic "[ERR][Viz.Phylo.Tools.getSensibility] sensibility not in params"


-- | To get the PhyloGroupId of the Source of a PhyloEdge 
getSourceId :: PhyloEdge -> PhyloGroupId
getSourceId e = e ^. phylo_edgeSource 


-- | To get the PhyloGroupId of the Target of a PhyloEdge
getTargetId :: PhyloEdge -> PhyloGroupId
getTargetId e = e ^. phylo_edgeTarget


-- | To get the Grain of the PhyloPeriods from a PhyloQuery
getTimeGrain :: PhyloQuery -> Int
getTimeGrain q = q ^. phyloQuery_timeGrain 


-- | To get the intertemporal matching strategy to apply to a Phylo from a PhyloQuery
getTimeMatching :: PhyloQuery -> Proximity
getTimeMatching q = q ^. phyloQuery_timeMatching


-- | To get the Steps of the PhyloPeriods from a PhyloQuery
getTimeSteps :: PhyloQuery -> Int 
getTimeSteps q = q ^. phyloQuery_timeSteps


-- | To get all the PhyloBranchIds of a PhyloView
getViewBranchIds :: PhyloView -> [PhyloBranchId]
getViewBranchIds v = map getBranchId $ v ^. phylo_viewBranches


-- | To init the foundation of the Phylo as a Vector of Ngrams 
initFoundations :: [Ngrams] -> Vector Ngrams
initFoundations l = Vector.fromList $ map toLower l


-- | To create a PhyloGroup in a Phylo out of a list of Ngrams and a set of parameters 
initGroup :: [Ngrams] -> Text -> Int -> Int -> Int -> Int -> Phylo -> PhyloGroup
initGroup ngrams lbl idx lvl from to p = PhyloGroup 
  (((from, to), lvl), idx)
  lbl
  (sort $ map (\x -> getIdxInFoundations x p) ngrams)
  (Map.empty)
  (Map.empty)
  Nothing
  [] [] [] []


-- | To init the Base of a Phylo from a List of Periods and Foundations
initPhyloBase :: [(Date, Date)] -> Vector Ngrams -> Phylo
initPhyloBase pds fds = Phylo ((fst . head) pds, (snd . last) pds) fds (map (\pd -> initPhyloPeriod pd []) pds)


-- | To create a PhyloLevel
initPhyloLevel :: PhyloLevelId -> [PhyloGroup] -> PhyloLevel
initPhyloLevel id groups = PhyloLevel id groups


-- | To create a PhyloPeriod
initPhyloPeriod :: PhyloPeriodId -> [PhyloLevel] -> PhyloPeriod
initPhyloPeriod id l = PhyloPeriod id l


-- | To filter Fis with small Support but by keeping non empty Periods
keepFilled :: (Int -> [a] -> [a]) -> Int -> [a] -> [a] 
keepFilled f thr l = if (null $ f thr l) && (not $ null l)
                     then keepFilled f (thr - 1) l
                     else f thr l  


-- | To get all combinations of a list
listToDirectedCombi :: Eq a => [a] -> [(a,a)]
listToDirectedCombi l = [(x,y) | x <- l, y <- l, x /= y]


-- | To get all combinations of a list and apply a function to the resulting list of pairs
listToDirectedCombiWith :: Eq a => forall b. (a -> b) -> [a] -> [(b,b)]
listToDirectedCombiWith f l = [(f x,f y) | x <- l, y <- l, x /= y]


-- | To get all combinations of a list with no repetition
listToUnDirectedCombi :: [a] -> [(a,a)]
listToUnDirectedCombi l = [ (x,y) | (x:rest) <- tails l,  y <- rest ]


-- | To get all combinations of a list with no repetition and apply a function to the resulting list of pairs
listToUnDirectedCombiWith :: forall a b. (a -> b) -> [a] -> [(b,b)]
listToUnDirectedCombiWith f l = [ (f x, f y) | (x:rest) <- tails l,  y <- rest ]


-- | To set the LevelId of a PhyloLevel and of all its PhyloGroups
setPhyloLevelId :: Int -> PhyloLevel -> PhyloLevel
setPhyloLevelId lvl' (PhyloLevel (id, lvl) groups)
    = PhyloLevel (id, lvl') groups'
        where 
            groups' = over (traverse . phylo_groupId) (\((period, lvl), idx) -> ((period, lvl'), idx)) groups 


-- | To unify the keys (x,y) that Map 1 share with Map 2 such as: (x,y) <=> (y,x)
unifySharedKeys :: Eq a => Ord a => Map (a,a) b -> Map (a,a) b -> Map (a,a) b
unifySharedKeys m1 m2 = mapKeys (\(x,y) -> if member (y,x) m2
                                           then (y,x)
                                           else (x,y) ) m1 