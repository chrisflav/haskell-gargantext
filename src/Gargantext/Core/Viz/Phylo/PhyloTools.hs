{-|
Module      : Gargantext.Core.Viz.Phylo.PhyloTools
Description : Module dedicated to all the tools needed for making a Phylo
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX
-}

{-# LANGUAGE ViewPatterns      #-}

module Gargantext.Core.Viz.Phylo.PhyloTools where

import Control.Lens hiding (Level)
import Data.List (sort, concat, null, union, (++), tails, sortOn, nub, init, tail, iterate, transpose, partition, tails, nubBy, group, notElem, (!!))
import Data.Map (Map, elems, fromList, unionWith, keys, member, (!), filterWithKey, fromListWith, empty, restrictKeys)
import Data.Set (Set, disjoint)
import Data.String (String)
import Data.Text (Text,unpack)
import Data.Vector (Vector, elemIndex)
import Debug.Trace (trace)
import Gargantext.Core.Viz.Phylo
import Gargantext.Prelude
import Prelude (floor,read)
import Text.Printf
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import qualified Data.Map as Map

------------
-- | Io | --
------------

-- | To print an important message as an IO()
printIOMsg :: String -> IO ()
printIOMsg msg =
    putStrLn ( "\n"
            <> "------------"
            <> "\n"
            <> "-- | " <> msg <> "\n" )


-- | To print a comment as an IO()
printIOComment :: String -> IO ()
printIOComment cmt =
    putStrLn ( "\n" <> cmt <> "\n" )


--------------
-- | Misc | --
--------------

-- truncate' :: Double -> Int -> Double
-- truncate' x n = (fromIntegral (floor (x * t))) / t
--     where t = 10^n

truncate' :: Double -> Int -> Double
truncate' x n = (fromIntegral $ (floor (x * t) :: Int)) / t
    where
        --------------
        t :: Double
        t = 10 ^n

getInMap :: Int -> Map Int Double -> Double
getInMap k m =
    if (member k m)
        then m ! k
        else 0

roundToStr :: (PrintfArg a, Floating a) => Int -> a -> String
roundToStr = printf "%0.*f"


countSup :: Double -> [Double] -> Int
countSup s l = length $ filter (>s) l


dropByIdx :: Int -> [a] -> [a]
dropByIdx k l = take k l ++ drop (k+1) l


elemIndex' :: Eq a => a -> [a] -> Int
elemIndex' e l = case (List.elemIndex e l) of
    Nothing -> panic ("[ERR][Viz.Phylo.PhyloTools] element not in list")
    Just i  -> i


commonPrefix :: Eq a => [a] -> [a] -> [a] -> [a]
commonPrefix lst lst' acc =
    if (null lst || null lst')
        then acc
        else if (head' "commonPrefix" lst == head' "commonPrefix" lst')
                then commonPrefix (tail lst) (tail lst') (acc ++ [head' "commonPrefix" lst])
                else acc


---------------------
-- | Foundations | --
---------------------


-- | Is this Ngrams a Foundations Root ?
isRoots :: Ngrams -> Vector Ngrams -> Bool
isRoots n ns = Vector.elem n ns

-- | To transform a list of nrams into a list of foundation's index
ngramsToIdx :: [Ngrams] -> Vector Ngrams -> [Int]
ngramsToIdx ns fdt = map (\n -> fromJust $ elemIndex n fdt) ns

-- | To transform a list of sources into a list of sources' index
sourcesToIdx :: [Text] -> Vector Text -> [Int]
sourcesToIdx ss ps = nub $ map (\s -> fromJust $ elemIndex s ps) ss

-- | To transform a list of Ngrams Indexes into a Label
ngramsToLabel :: Vector Ngrams -> [Int] -> Text
ngramsToLabel ngrams l = Text.unwords $ tail' "ngramsToLabel" $ concat $ map (\n -> ["|",n]) $ ngramsToText ngrams l

idxToLabel :: [Int] -> String
idxToLabel l = List.unwords $ tail' "idxToLabel" $ concat $ map (\n -> ["|",show n]) l

idxToLabel' :: [Double] -> String
idxToLabel' l = List.unwords $ tail' "idxToLabel" $ concat $ map (\n -> ["|",show n]) l

-- | To transform a list of Ngrams Indexes into a list of Text
ngramsToText :: Vector Ngrams -> [Int] -> [Text]
ngramsToText ngrams l = map (\idx -> ngrams Vector.! idx) l


--------------
-- | Time | --
--------------

-- | To transform a list of periods into a set of Dates
periodsToYears :: [(Date,Date)] -> Set Date
periodsToYears periods = (Set.fromList . sort . concat)
                       $ map (\(d,d') -> [d..d']) periods


findBounds :: [Date] -> (Date,Date)
findBounds dates =
    let dates' = sort dates
    in  (head' "findBounds" dates', last' "findBounds" dates')


toPeriods :: [Date] -> Int -> Int -> [(Date,Date)]
toPeriods dates p s =
    let (start,end) = findBounds dates
    in map (\dates' -> (head' "toPeriods" dates', last' "toPeriods" dates'))
     $ chunkAlong p s [start .. end]


toFstDate :: [Text] -> Text
toFstDate ds = snd
             $ head' "firstDate"
             $ sortOn fst
             $ map (\d ->
                      let d' = read (filter (\c -> notElem c ['U','T','C',' ',':','-']) $ unpack d)::Int
                       in (d',d)) ds

toLstDate :: [Text] -> Text
toLstDate ds = snd
             $ head' "firstDate"
             $ reverse
             $ sortOn fst
             $ map (\d ->
                      let d' = read (filter (\c -> notElem c ['U','T','C',' ',':','-']) $ unpack d)::Int
                       in (d',d)) ds


getTimeScale :: Phylo -> [Char]
getTimeScale p = case (timeUnit $ getConfig p) of
    Epoch _ _ _ -> "epoch"
    Year  _ _ _ -> "year"
    Month _ _ _ -> "month"
    Week  _ _ _ -> "week"
    Day   _ _ _ -> "day"


-- | Get a regular & ascendante timeScale from a given list of dates
toTimeScale :: [Date] -> Int -> [Date]
toTimeScale dates step =
    let (start,end) = findBounds dates
    in  [start, (start + step) .. end]


getTimeStep :: TimeUnit -> Int
getTimeStep time = case time of
    Epoch _ s _ -> s
    Year  _ s _ -> s
    Month _ s _ -> s
    Week  _ s _ -> s
    Day   _ s _ -> s

getTimePeriod :: TimeUnit -> Int
getTimePeriod time = case time of
    Epoch p _ _ -> p
    Year  p _ _ -> p
    Month p _ _ -> p
    Week  p _ _ -> p
    Day   p _ _ -> p

getTimeFrame :: TimeUnit -> Int
getTimeFrame time = case time of
    Epoch _ _ f -> f
    Year  _ _ f -> f
    Month _ _ f -> f
    Week  _ _ f -> f
    Day   _ _ f -> f

-------------
-- | Fis | --
-------------


-- | To find if l' is nested in l
isNested :: Eq a => [a] -> [a] -> Bool
isNested l l'
  | null l'               = True
  | length l' > length l  = False
  | (union  l l') == l    = True
  | otherwise             = False


-- | To filter Fis with small Support but by keeping non empty Periods
keepFilled :: (Int -> [a] -> [a]) -> Int -> [a] -> [a]
keepFilled f thr l = if (null $ f thr l) && (not $ null l)
                     then keepFilled f (thr - 1) l
                     else f thr l


traceClique :: Map (Date, Date) [Clustering] -> String
traceClique mFis = foldl (\msg cpt -> msg <> show (countSup cpt cliques) <> " (>" <> show (cpt) <> ") "  ) "" [1..6]
    where
        --------------------------------------
        cliques :: [Double]
        cliques = sort $ map (fromIntegral . length . _clustering_roots) $ concat $ elems mFis
        --------------------------------------


traceSupport :: Map (Date, Date) [Clustering] -> String
traceSupport mFis = foldl (\msg cpt -> msg <> show (countSup cpt supports) <> " (>" <> show (cpt) <> ") "  ) "" [1..6]
    where
        --------------------------------------
        supports :: [Double]
        supports = sort $ map (fromIntegral . _clustering_support) $ concat $ elems mFis
        --------------------------------------


traceFis :: [Char] -> Map (Date, Date) [Clustering] -> Map (Date, Date) [Clustering]
traceFis msg mFis = trace ( "\n" <> "-- | " <> msg <> " : " <> show (sum $ map length $ elems mFis) <> "\n"
                         <> "Support : " <> (traceSupport mFis) <> "\n"
                         <> "Nb Ngrams : "  <> (traceClique mFis)  <> "\n" ) mFis


----------------
-- | Cluster| --
----------------


getCliqueSupport :: Cluster -> Int
getCliqueSupport unit = case unit of
    Fis s _ -> s
    MaxClique _ _ _ -> 0

getCliqueSize :: Cluster -> Int
getCliqueSize unit = case unit of
    Fis _ s -> s
    MaxClique s _ _ -> s


--------------
-- | Cooc | --
--------------

listToCombi' :: [a] -> [(a,a)]
listToCombi' l = [(x,y) | (x:rest) <- tails l,  y <- rest]

listToEqual' :: Eq a => [a] -> [(a,a)]
listToEqual' l = [(x,y) | x <- l, y <- l, x == y]

listToKeys :: Eq a =>  [a] -> [(a,a)]
listToKeys lst = (listToCombi' lst) ++ (listToEqual' lst)

listToMatrix :: [Int] -> Map (Int,Int) Double
listToMatrix lst = fromList $ map (\k -> (k,1)) $ listToKeys $ sort lst

listToMatrix' :: [Ngrams] -> Map (Ngrams,Ngrams) Int
listToMatrix' lst = fromList $ map (\k -> (k,1)) $ listToKeys $ sort lst

listToSeq :: Eq a =>  [a] -> [(a,a)]
listToSeq l = nubBy (\x y -> fst x == fst y) $ [ (x,y) | (x:rest) <- tails l,  y <- rest ]

sumCooc :: Cooc -> Cooc -> Cooc
sumCooc cooc cooc' = unionWith (+) cooc cooc'

getTrace :: Cooc -> Double
getTrace cooc = sum $ elems $ filterWithKey (\(k,k') _ -> k == k') cooc

coocToDiago :: Cooc -> Cooc
coocToDiago cooc = filterWithKey (\(k,k') _ -> k == k') cooc

coocToAdjacency :: Cooc -> Cooc
coocToAdjacency cooc = Map.map (\_ -> 1) cooc

-- | To build the local cooc matrix of each phylogroup
ngramsToCooc :: [Int] -> [Cooc] -> Cooc
ngramsToCooc ngrams coocs =
    let cooc  = foldl (\acc cooc' -> sumCooc acc cooc') empty coocs
        pairs = listToKeys ngrams
    in  filterWithKey (\k _ -> elem k pairs) cooc


------------------
-- | Defaults | --
------------------

-- | find the local maxima in a list of values
findMaxima :: [(Double,Double)] -> [Bool]
findMaxima lst = map (hasMax) $ toChunk 3 lst
    where
        ------
        hasMax :: [(Double,Double)] -> Bool
        hasMax chunk = 
            if (length chunk) /= 3
                then False
                else (snd(chunk !! 0) < snd(chunk !! 1)) && (snd(chunk !! 2) < snd(chunk !! 1))


-- | split a list into chunks of size n
toChunk :: Int -> [a] -> [[a]]
toChunk n = takeWhile ((== n) . length) . transpose . take n . iterate tail      


-- | To compute the average degree from a cooc matrix
--   http://networksciencebook.com/chapter/2#degree
toAverageDegree :: Cooc -> Vector Ngrams -> Double
toAverageDegree cooc roots = 2 * (fromIntegral $ Map.size cooc) / (fromIntegral $ Vector.length roots)


-- | Use the giant component regime to estimate the default level
--   http://networksciencebook.com/chapter/3#networks-supercritical
regimeToDefaultLevel :: Cooc -> Vector Ngrams -> Double
regimeToDefaultLevel cooc roots 
    | avg == 0  = 1
    | avg < 1   = avg * 0.6
    | avg == 1  = 0.6
    | avg < lnN = (avg * 0.2) / lnN
    | otherwise = 0.2
    where
        avg :: Double
        avg = toAverageDegree cooc roots
        lnN :: Double
        lnN = log (fromIntegral $ Vector.length roots)

coocToConfidence :: Phylo -> Cooc
coocToConfidence phylo = 
    let count = getRootsCount phylo
        cooc  = foldl (\acc cooc' -> sumCooc acc cooc') empty 
              $ elems $ getCoocByDate phylo
     in Map.mapWithKey (\(a,b) w -> confidence a b w count) cooc
    where 
        ----
        -- confidence
        confidence :: Int -> Int -> Double -> Map Int Double -> Double
        confidence a b inter card = maximum [(inter / card ! a),(inter / card ! b)]


sumtest :: [Int] -> [Int] -> Int 
sumtest l1 l2 = (head' "test" l1) + (head' "test" $ reverse l2)


findDefaultLevel :: Phylo -> Phylo
findDefaultLevel phylo = 
    let confidence = Map.filterWithKey (\(a,b) _ -> a /= b) 
                   $ Map.filter (> 0.01) 
                   $ coocToConfidence phylo
        roots = getRoots phylo
        level = regimeToDefaultLevel confidence roots
     in updateLevel level phylo


--------------------
-- | PhyloGroup | --
--------------------

getGroupId :: PhyloGroup -> PhyloGroupId
getGroupId g = ((g ^. phylo_groupPeriod, g ^. phylo_groupScale), g ^. phylo_groupIndex)

getGroupNgrams :: PhyloGroup -> [Int]
getGroupNgrams g = g ^. phylo_groupNgrams

idToPrd :: PhyloGroupId -> Period
idToPrd id = (fst . fst) id

groupByField :: Ord a => (PhyloGroup -> a) -> [PhyloGroup] ->  Map a [PhyloGroup]
groupByField toField groups = fromListWith (++) $ map (\g -> (toField g, [g])) groups

getPeriodPointers :: Filiation -> PhyloGroup -> [Pointer]
getPeriodPointers fil g =
    case fil of
        ToChilds  -> g ^. phylo_groupPeriodChilds
        ToParents -> g ^. phylo_groupPeriodParents
        ToChildsMemory  -> undefined
        ToParentsMemory -> undefined

filterSimilarity :: PhyloSimilarity -> Double -> Double -> Bool
filterSimilarity similarity thr local =
    case similarity of
        WeightedLogJaccard _ _ -> local >= thr
        WeightedLogSim     _ _ -> local >= thr
        Hamming            _ _ -> undefined

getSimilarityName :: PhyloSimilarity -> String
getSimilarityName similarity =
    case similarity of
        WeightedLogJaccard _ _ -> "WLJaccard"
        WeightedLogSim     _ _ -> "WeightedLogSim"
        Hamming            _ _ -> "Hamming"

---------------
-- | Phylo | --
---------------

addPointers :: Filiation -> PointerType -> [Pointer] -> PhyloGroup -> PhyloGroup
addPointers fil pty pointers g =
    case pty of
        TemporalPointer -> case fil of
                                ToChilds  -> g & phylo_groupPeriodChilds  .~ pointers
                                ToParents -> g & phylo_groupPeriodParents .~ pointers
                                ToChildsMemory  -> undefined
                                ToParentsMemory -> undefined
        ScalePointer    -> case fil of
                                ToChilds  -> g & phylo_groupScaleChilds   .~ pointers
                                ToParents -> g & phylo_groupScaleParents  .~ pointers
                                ToChildsMemory  -> undefined
                                ToParentsMemory -> undefined

toPointer' :: Double -> Pointer -> Pointer'
toPointer' thr pt = (fst pt,(thr,snd pt))


addMemoryPointers :: Filiation -> PointerType -> Double -> [Pointer] -> PhyloGroup -> PhyloGroup
addMemoryPointers fil pty thr pointers g =
    case pty of
        TemporalPointer -> case fil of
                                ToChilds  -> undefined
                                ToParents -> undefined
                                ToChildsMemory  -> g & phylo_groupPeriodMemoryChilds  .~ (concat [(g ^. phylo_groupPeriodMemoryChilds),(map (\pt -> toPointer' thr pt) pointers)])
                                ToParentsMemory -> g & phylo_groupPeriodMemoryParents .~ (concat [(g ^. phylo_groupPeriodMemoryParents),(map (\pt -> toPointer' thr pt) pointers)])
        ScalePointer    -> undefined


getPeriodIds :: Phylo -> [(Date,Date)]
getPeriodIds phylo = sortOn fst
                   $ keys
                   $ phylo ^. phylo_periods

getLevelParentId :: PhyloGroup -> PhyloGroupId
getLevelParentId g = fst $ head' "getLevelParentId" $ g ^. phylo_groupScaleParents

getLastLevel :: Phylo -> Scale
getLastLevel phylo = last' "lastLevel" $ getScales phylo

getScales :: Phylo -> [Scale]
getScales phylo = nub
                $ map snd
                $ keys $ view ( phylo_periods
                       .  traverse
                       . phylo_periodScales ) phylo

getSeaElevation :: Phylo -> SeaElevation
getSeaElevation phylo = seaElevation (getConfig phylo)

getSimilarity :: Phylo -> PhyloSimilarity
getSimilarity phylo = similarity (getConfig phylo)


getPhyloSeaRiseStart :: Phylo -> Double
getPhyloSeaRiseStart phylo = case (getSeaElevation phylo) of
    Constante  s _ -> s
    Adaptative _ -> 0
    Evolving   _ -> 0

getPhyloSeaRiseSteps :: Phylo -> Double
getPhyloSeaRiseSteps phylo = case (getSeaElevation phylo) of
    Constante  _ s -> s
    Adaptative s -> s
    Evolving   _ -> 0.1    


getConfig :: Phylo -> PhyloConfig
getConfig phylo = (phylo ^. phylo_param) ^. phyloParam_config

getLevel :: Phylo -> Double
getLevel phylo = _phylo_level phylo

getLadder :: Phylo -> [Double]
getLadder phylo = phylo ^. phylo_seaLadder

getCoocByDate :: Phylo -> Map Date Cooc
getCoocByDate phylo = coocByDate (phylo ^. phylo_counts)    

getDocsByDate :: Phylo -> Map Date Double
getDocsByDate phylo = docsByDate (phylo ^. phylo_counts) 

getRootsCount :: Phylo -> Map Int  Double
getRootsCount phylo = rootsCount (phylo ^. phylo_counts)

getRootsFreq :: Phylo -> Map Int  Double
getRootsFreq phylo = rootsFreq (phylo ^. phylo_counts)

getLastRootsFreq :: Phylo -> Map Int  Double
getLastRootsFreq phylo = lastRootsFreq (phylo ^. phylo_counts)

setConfig :: PhyloConfig -> Phylo -> Phylo
setConfig config phylo = phylo
                       & phylo_param .~ (PhyloParam
                                            ((phylo ^. phylo_param) ^. phyloParam_version)
                                            ((phylo ^. phylo_param) ^. phyloParam_software)
                                            config)

-- & phylo_param & phyloParam_config & phyloParam_config .~ config


getRoots :: Phylo -> Vector Ngrams
getRoots phylo = (phylo ^. phylo_foundations) ^. foundations_roots

getRootsInGroups :: Phylo -> Map Int [PhyloGroupId]
getRootsInGroups phylo = (phylo ^. phylo_foundations) ^. foundations_rootsInGroups

getSources :: Phylo -> Vector Text
getSources phylo = _sources (phylo ^. phylo_sources)


-- get the groups distributed by branches at the last scale
phyloLastScale :: Phylo -> [[PhyloGroup]]
phyloLastScale phylo = elems
    $ fromListWith (++)
    $ map (\g -> (g ^. phylo_groupBranchId, [g]))
    $ getGroupsFromScale (last' "byBranches" $ getScales phylo) phylo

getGroupsFromScale :: Scale -> Phylo -> [PhyloGroup]
getGroupsFromScale lvl phylo =
    elems $ view ( phylo_periods
                 .  traverse
                 . phylo_periodScales
                 .  traverse
                 .  filtered (\phyloLvl -> phyloLvl ^. phylo_scaleScale == lvl)
                 . phylo_scaleGroups ) phylo


getGroupsFromScalePeriods :: Scale -> [Period] -> Phylo -> [PhyloGroup]
getGroupsFromScalePeriods lvl periods phylo =
    elems $ view ( phylo_periods
                 .  traverse
                 .  filtered (\phyloPrd -> elem (phyloPrd ^. phylo_periodPeriod) periods)
                 . phylo_periodScales
                 .  traverse
                 .  filtered (\phyloLvl -> phyloLvl ^. phylo_scaleScale == lvl)
                 . phylo_scaleGroups ) phylo


getGroupsFromPeriods :: Scale -> Map Period PhyloPeriod -> [PhyloGroup]
getGroupsFromPeriods lvl periods =
    elems $ view (  traverse
                 . phylo_periodScales
                 .  traverse
                 .  filtered (\phyloLvl -> phyloLvl ^. phylo_scaleScale == lvl)
                 . phylo_scaleGroups ) periods


updatePhyloGroups :: Scale -> Map PhyloGroupId PhyloGroup -> Phylo -> Phylo
updatePhyloGroups lvl m phylo =
    over ( phylo_periods
         .  traverse
         . phylo_periodScales
         .  traverse
         .  filtered (\phyloLvl -> phyloLvl ^. phylo_scaleScale == lvl)
         . phylo_scaleGroups
         .  traverse
         ) (\g ->
                let id = getGroupId g
                in
                    if member id m
                    then m ! id
                    else g ) phylo

updatePeriods :: Map (Date,Date) (Text,Text) -> Phylo -> Phylo
updatePeriods periods' phylo =
    over (phylo_periods . traverse)
            (\prd ->
                let prd' = periods' ! (prd ^. phylo_periodPeriod)
                    lvls = map (\lvl -> lvl & phylo_scalePeriodStr .~ prd') $ prd ^. phylo_periodScales
                 in prd & phylo_periodPeriodStr .~ prd'
                        & phylo_periodScales    .~ lvls
                ) phylo

updateQuality :: Double -> Phylo -> Phylo
updateQuality quality phylo = phylo { _phylo_quality = quality } 

updateLevel :: Double -> Phylo -> Phylo
updateLevel level phylo = phylo { _phylo_level = level } 

traceToPhylo :: Scale -> Phylo -> Phylo
traceToPhylo lvl phylo =
    trace ("\n" <> "-- | End of phylo making at level " <> show (lvl) <> " with "
                <> show (length $ getGroupsFromScale lvl phylo) <> " groups and "
                <> show (length $ nub $ map _phylo_groupBranchId $ getGroupsFromScale lvl phylo) <> " branches" <> "\n") phylo

--------------------
-- | Clustering | --
--------------------

mergeBranchIds :: [[Int]] -> [Int]
mergeBranchIds ids = (head' "mergeBranchIds" . sort . mostFreq') ids
  where
    -- | 2) find the most Up Left ids in the hierarchy of similarity
    -- mostUpLeft :: [[Int]] -> [[Int]]
    -- mostUpLeft ids' =
    --      let groupIds = (map (\gIds -> (length $ head' "gIds" gIds, head' "gIds" gIds)) . groupBy (\id id' -> length id == length id') . sortOn length) ids'
    --          inf = (fst . minimum) groupIds
    --      in map snd $ filter (\gIds -> fst gIds == inf) groupIds
    -- | 1) find the most frequent ids
    mostFreq' :: [[Int]] -> [[Int]]
    mostFreq' ids' =
       let groupIds = (map (\gIds -> (length gIds, head' "gIds" gIds)) . group . sort) ids'
           sup = (fst . maximum) groupIds
        in map snd $ filter (\gIds -> fst gIds == sup) groupIds


mergeMeta :: [Int] -> [PhyloGroup] -> Map Text [Double]
mergeMeta bId groups =
  let ego = head' "mergeMeta" $ filter (\g -> (snd (g ^. phylo_groupBranchId)) == bId) groups
   in fromList [("breaks",(ego ^. phylo_groupMeta) ! "breaks"),("seaLevels",(ego ^. phylo_groupMeta) ! "seaLevels")]


groupsToBranches' :: Map PhyloGroupId PhyloGroup -> [[PhyloGroup]]
groupsToBranches' groups =
    {- run the related component algorithm -}
    let egos  = map (\g -> [getGroupId g]
                        ++ (map fst $ g ^. phylo_groupPeriodParents)
                        ++ (map fst $ g ^. phylo_groupPeriodChilds)
                        ++ (map fst $ g ^. phylo_groupAncestors)) $ elems groups
        graph = relatedComponents egos
    {- update each group's branch id -}
    in map (\ids ->
        let groups' = elems $ restrictKeys groups (Set.fromList ids)
            bId = mergeBranchIds $ map (\g -> snd $ g ^. phylo_groupBranchId) groups'
         in map (\g -> g & phylo_groupBranchId %~ (\(lvl,_) -> (lvl,bId))) groups') graph


relatedComponents :: Ord a => [[a]] -> [[a]]
relatedComponents graph = foldl' (\branches groups ->
    if (null branches)
    then branches ++ [groups]
    else
        let branchPart = partition (\branch -> disjoint (Set.fromList branch) (Set.fromList groups)) branches
         in (fst branchPart) ++ [nub $ concat $ (snd branchPart) ++ [groups]]) [] graph


toRelatedComponents :: [PhyloGroup] -> [((PhyloGroup,PhyloGroup),Double)] -> [[PhyloGroup]]
toRelatedComponents nodes edges =
  let ref = fromList $ map (\g -> (getGroupId g, g)) nodes
      clusters = relatedComponents $ ((map (\((g,g'),_) -> [getGroupId g, getGroupId g']) edges) ++ (map (\g -> [getGroupId g]) nodes))
   in map (\cluster -> map (\gId -> ref ! gId) cluster) clusters


traceSynchronyEnd :: Phylo -> Phylo
traceSynchronyEnd phylo =
    trace ( "-- | End synchronic clustering at level " <> show (getLastLevel phylo)
                 <> " with " <> show (length $ getGroupsFromScale (getLastLevel phylo) phylo) <> " groups"
                 <> " and "  <> show (length $ nub $ map _phylo_groupBranchId $ getGroupsFromScale (getLastLevel phylo) phylo) <> " branches"
                 <> "\n" ) phylo

traceSynchronyStart :: Phylo -> Phylo
traceSynchronyStart phylo =
    trace ( "\n" <> "-- | Start synchronic clustering at level " <> show (getLastLevel phylo)
                 <> " with " <> show (length $ getGroupsFromScale (getLastLevel phylo) phylo) <> " groups"
                 <> " and "  <> show (length $ nub $ map _phylo_groupBranchId $ getGroupsFromScale (getLastLevel phylo) phylo) <> " branches"
                 <> "\n" ) phylo


-------------------
-- | Similarity | --
-------------------

getSensibility :: PhyloSimilarity -> Double
getSensibility proxi = case proxi of
    WeightedLogJaccard s _ -> s
    WeightedLogSim     s _ -> s
    Hamming            _ _ -> undefined

getMinSharedNgrams :: PhyloSimilarity -> Int
getMinSharedNgrams proxi = case proxi of
    WeightedLogJaccard _ m -> m
    WeightedLogSim     _ m -> m
    Hamming            _ _ -> undefined    

----------------
-- | Branch | --
----------------

intersectInit :: Eq a => [a] -> [a] -> [a] -> [a]
intersectInit acc lst lst' =
    if (null lst) || (null lst')
    then acc
    else if (head' "intersectInit" lst) == (head' "intersectInit" lst')
         then intersectInit (acc ++ [head' "intersectInit" lst]) (tail lst) (tail lst')
         else acc

branchIdsToSimilarity :: PhyloBranchId -> PhyloBranchId -> Double -> Double -> Double
branchIdsToSimilarity id id' thrInit thrStep = thrInit + thrStep * (fromIntegral $ length $ intersectInit [] (snd id) (snd id'))

ngramsInBranches :: [[PhyloGroup]] -> [Int]
ngramsInBranches branches = nub $ foldl (\acc g -> acc ++ (g ^. phylo_groupNgrams)) [] $ concat branches


traceMatchSuccess :: Double -> Double -> Double -> [[[PhyloGroup]]] -> [[[PhyloGroup]]]
traceMatchSuccess thr qua qua' nextBranches =
    trace ( "\n" <> "-- local branches : " <> (init $ show ((init . init . snd)
                                                    $ (head' "trace" $ head' "trace" $ head' "trace" nextBranches) ^. phylo_groupBranchId))
                                           <> ",(1.." <> show (length nextBranches) <> ")]"
                 <> " | " <> show ((length . concat . concat) nextBranches) <> " groups" <> "\n"
         <> " - splited with success in "  <> show (map length nextBranches) <> " sub-branches" <> "\n"
         <> " - for the local threshold "  <> show (thr) <> " ( quality : " <> show (qua) <> " < " <> show(qua') <> ")\n" ) nextBranches


traceMatchFailure :: Double -> Double -> Double -> [[PhyloGroup]] -> [[PhyloGroup]]
traceMatchFailure thr qua qua' branches =
    trace ( "\n" <> "-- local branches : " <> (init $ show ((init . snd) $ (head' "trace" $ head' "trace" branches) ^. phylo_groupBranchId))
                                           <> ",(1.." <> show (length branches) <> ")]"
                 <> " | " <> show (length $ concat branches) <> " groups" <> "\n"
         <> " - split with failure for the local threshold " <> show (thr) <> " ( quality : " <> show (qua) <> " > " <> show(qua') <> ")\n"
        ) branches


traceMatchNoSplit :: [[PhyloGroup]] -> [[PhyloGroup]]
traceMatchNoSplit branches =
    trace ( "\n" <> "-- local branches : " <> (init $ show ((init . snd) $ (head' "trace" $ head' "trace" branches) ^. phylo_groupBranchId))
                                           <> ",(1.." <> show (length branches) <> ")]"
                 <> " | " <> show (length $ concat branches) <> " groups" <> "\n"
         <> " - unable to split in smaller branches" <> "\n"
        ) branches


traceMatchLimit :: [[PhyloGroup]] -> [[PhyloGroup]]
traceMatchLimit branches =
    trace ( "\n" <> "-- local branches : " <> (init $ show ((init . snd) $ (head' "trace" $ head' "trace" branches) ^. phylo_groupBranchId))
                                           <> ",(1.." <> show (length branches) <> ")]"
                 <> " | " <> show (length $ concat branches) <> " groups" <> "\n"
         <> " - unable to increase the threshold above 1" <> "\n"
        ) branches


traceMatchEnd :: [PhyloGroup] -> [PhyloGroup]
traceMatchEnd groups =
    trace ("\n" <> "-- | End temporal matching with " <> show (length $ nub $ map (\g -> g ^. phylo_groupBranchId) groups)
                                                         <> " branches and " <> show (length groups) <> " groups" <> "\n") groups


traceTemporalMatching :: [PhyloGroup] -> [PhyloGroup]
traceTemporalMatching groups =
    trace ( "\n" <> "-- | Start temporal matching for " <> show(length groups) <> " groups" <> "\n") groups


traceGroupsProxi :: [Double] -> [Double]
traceGroupsProxi l =
    trace ( "\n" <> "-- | " <> show(List.length l) <> " computed pairs of groups Similarity" <> "\n") l
