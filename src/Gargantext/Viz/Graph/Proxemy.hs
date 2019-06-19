{-| Module      : Gargantext.Viz.Graph.Proxemy
Description : Proxemy
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

Références:
- Bruno Gaume, Karine Duvignau, Emmanuel Navarro, Yann Desalle, Hintat Cheung, et al.. Skillex: a graph-based lexical score for measuring the semantic efficiency of used verbs by human subjects describing actions. Revue TAL, Association pour le Traitement Automatique des Langues, 2016, Revue TAL : numéro spécial sur Traitement Automatique des Langues et Sciences Cognitives (55-3), 55 (3), ⟨https://www.atala.org/-Cognitive-Issues-in-Natural-⟩. ⟨hal-01320416⟩

- Implémentation Python [Lien]()

-}

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Gargantext.Viz.Graph.Proxemy
  where

--import Debug.SimpleReflect
import Gargantext.Prelude
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.List as List
--import Gargantext.Viz.Graph.IGraph
import Gargantext.Viz.Graph.FGL

type Length = Int
type FalseReflexive = Bool
type NeighborsFilter = Graph_Undirected -> Node -> [Node]
type We = Bool

confluence :: [(Node,Node)] -> Length -> FalseReflexive -> We -> Map (Node,Node) Double
confluence ns l fr we = similarity_conf (mkGraphUfromEdges ns) l fr we

similarity_conf :: Graph_Undirected -> Length -> FalseReflexive -> We -> Map (Node,Node) Double
similarity_conf g l fr we = Map.fromList [ ((x,y), similarity_conf_x_y g (x,y) l fr we)
                                         | x <- nodes g, y <- nodes g, x < y]

similarity_conf_x_y :: Graph_Undirected -> (Node,Node) -> Length -> FalseReflexive -> We -> Double
similarity_conf_x_y g (x,y) l r we = similarity
  where
    similarity :: Double
    similarity | denominator == 0 = 0
               | otherwise        = prox_x_y / denominator
       where
         denominator = prox_x_y + lim_SC

    prox_x_y :: Double
    prox_x_y = maybe 0 identity $ Map.lookup y xline

    xline :: Map Node Double
    xline    = prox_markov g [x] l r filterNeighbors'
      where
        filterNeighbors' | we == True = filterNeighbors
                         | otherwise  = rm_edge_neighbors (x,y)

    pair_is_edge :: Bool
    pair_is_edge | we == True = False
                 | otherwise  = List.elem y (filterNeighbors g x)

    lim_SC :: Double
    lim_SC
          | denominator == 0 = 0
          | otherwise  = if pair_is_edge
                             then (degree g y + 1-1)  / denominator
                             else (degree g y + 1  ) / denominator
            where
              denominator = if pair_is_edge
                              then (2 * (ecount g) + (vcount g) - 2)
                              else (2 * (ecount g) + (vcount g)    )


rm_edge_neighbors :: (Node, Node) -> Graph_Undirected -> Node -> [Node]
rm_edge_neighbors (x,y) g n | (n == x && List.elem y all_neighbors) = List.filter (/= y) all_neighbors
                            | (n == y && List.elem x all_neighbors) = List.filter (/= x) all_neighbors
                            | otherwise                             = all_neighbors
                              where
                                all_neighbors = filterNeighbors g n


-- | TODO do as a Map instead of [Node] ?
prox_markov :: Graph_Undirected -> [Node] -> Length -> FalseReflexive -> NeighborsFilter -> Map Node Double
prox_markov g ns l r nf = foldl' (\m _ -> spreading g m r nf) ms path
  where
    path
      | l == 0  = []
      | l >  0  = [0..l-1]
      | otherwise = panic "Gargantext.Viz.Graph.Proxemy.prox_markov: Length < 0"
    -- TODO if ns empty
    ms = case List.length ns > 0 of
           True -> Map.fromList $ map (\n -> (n, 1 / (fromIntegral $ List.length ns))) ns
           _    -> Map.empty


spreading :: Graph_Undirected -> Map Node Double -> FalseReflexive -> NeighborsFilter -> Map Node Double
spreading g ms r nf = Map.fromListWith (+) $ List.concat $ map pvalue (Map.keys ms)
  where
    -- TODO if list empty ...
    -- pvalue' n = [pvalue n]  <> map pvalue (neighborhood n)
    pvalue n = [(n, pvalue' n)] <> map (\n''->(n'', pvalue' n)) (nf g n)
      where
        pvalue' n'    = (value n') / (fromIntegral $ List.length neighborhood)
        value   n'    = maybe 0 identity $ Map.lookup n' ms
        neighborhood  = (nf g n) <> (if r then [n] else [])


------------------------------------------------------------------------
-- | Graph Tools

filterNeighbors :: Graph_Undirected -> Node -> [Node]
filterNeighbors g n = List.nub $ neighbors g n

degree :: Graph_Undirected -> Node -> Double
degree g n = fromIntegral $ List.length (filterNeighbors g n)

vcount :: Graph_Undirected -> Double
vcount = fromIntegral . List.length . List.nub . nodes

-- | TODO tests, optim and use IGraph library, fix IO ?
ecount :: Graph_Undirected -> Double
ecount = fromIntegral . List.length . List.nub . edges

------------------------------------------------------------------------
-- | Behavior tests

graphTest :: Graph_Undirected
graphTest= mkGraphUfromEdges graphTest_data

graphTest_data :: [(Int,Int)]
graphTest_data = [(0,1),(0,2),(0,4),(0,5),(1,3),(1,8),(2,3),(2,4),(2,5),(2,6),(2,16),(3,4),(3,5),(3,6),(3,18),(4,6),(5,8),(7,8),(7,9),(7,10),(7,13),(8,9),(8,10),(8,11),(8,12),(8,13),(9,12),(9,13),(10,11),(10,17),(11,12),(13,20),(14,16),(14,17),(14,18),(14,20),(15,16),(15,17),(15,18),(15,20),(16,18),(16,20),(17,18),(17,20),(18,19),(18,20),(19,20)]

graphTest_data' :: [(Int,Int)]
graphTest_data' = [(0,1),(0,2),(0,4),(0,5),(1,0),(1,3),(1,8),(2,0),(2,3),(2,4),(2,5),(2,6),(2,16),(3,1),(3,2),(3,4),(3,5),(3,6),(3,18),(4,0),(4,2),(4,3),(4,6),(5,0),(5,2),(5,3),(5,8),(6,2),(6,3),(6,4),(7,8),(7,9),(7,10),(7,13),(8,1),(8,5),(8,7),(8,9),(8,10),(8,11),(8,12),(8,13),(9,7),(9,8),(9,12),(9,13),(10,7),(10,8),(10,11),(10,17),(11,8),(11,10),(11,12),(12,8),(12,9),(12,11),(13,7),(13,8),(13,9),(13,20),(14,16),(14,17),(14,18),(14,20),(15,16),(15,17),(15,18),(15,20),(16,2),(16,14),(16,15),(16,18),(16,20),(17,10),(17,14),(17,15),(17,18),(17,20),(18,3),(18,14),(18,15),(18,16),(18,17),(18,19),(18,20),(19,18),(19,20),(20,13),(20,14),(20,15),(20,16),(20,17),(20,18),(20,19)]

-- | Tests
-- >>> runTest_Confluence_Proxemy
-- (True,True)
runTest_Confluence_Proxemy :: (Bool, Bool)
runTest_Confluence_Proxemy = (runTest_conf_is_ok, runTest_prox_is_ok)
  where
    runTest_conf_is_ok :: Bool
    runTest_conf_is_ok = List.null $ List.filter (\t -> snd t == False)
                   [ (((x,y)), abs ((look (y,x) test) - (look (y,x) temoin)) < 0.0001)
                   | y <- nodes graphTest
                   , x <- nodes graphTest
                   ]

      where
        test = toMap [(n, [ (y, similarity_conf_x_y graphTest (n,y) 3 True False) | y <- nodes graphTest])
                     | n <- nodes graphTest
                     ]
        temoin = test_confluence_temoin

    runTest_prox_is_ok :: Bool
    runTest_prox_is_ok = List.null (List.filter (not . List.null) $ map runTest_prox' [0..3])


    runTest_prox' :: Node -> [((Node, (Node, Node)), Bool)]
    runTest_prox' l = List.filter (\t -> snd t == False)
                   [ ((l,(x,y)), abs ((look (y,x) test) - (look (y,x) temoin)) < 0.0001)
                   | y <- nodes graphTest
                   , x <- nodes graphTest
                   ]
      where
        test   = toMap $ test_proxs_y l
        temoin = toMap $ test_prox    l

        test_proxs_y :: Length -> [(Node, [(Node, Double)])]
        test_proxs_y l' = map (\n -> test_proxs_x l' n) (nodes graphTest)

        test_proxs_x :: Length -> Node -> (Node, [(Node, Double)])
        test_proxs_x l' a = (a, map (\x -> (x, maybe 0 identity $ Map.lookup x (m a))) (nodes graphTest))
          where
            m x' = prox_markov graphTest [x'] l' True filterNeighbors

    toMap  = Map.map Map.fromList . Map.fromList

    look :: (Node,Node) -> Map Node (Map Node Double) -> Double
    look (x,y) m = look' x $ look' y m
      where
        look' x' m' = maybe (panic "nokey") identity $ Map.lookup x' m'

--prox : longueur balade = 0
test_prox :: Node -> [(Node, [(Node, Double)])]
test_prox 0 = [ (0,[(0,1.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (1,[(0,0.0000),(1,1.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (2,[(0,0.0000),(1,0.0000),(2,1.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (3,[(0,0.0000),(1,0.0000),(2,0.0000),(3,1.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (4,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,1.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (5,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,1.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (6,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,1.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (7,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,1.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (8,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,1.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (9,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,1.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (10,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,1.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (11,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,1.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (12,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,1.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (13,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,1.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (14,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,1.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (15,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,1.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (16,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,1.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (17,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,1.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
  , (18,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,1.0000),(19,0.0000),(20,0.0000)])
  , (19,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,1.0000),(20,0.0000)])
  , (20,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,1.0000)])
  ]

--{-
--, longueur balade , 1]), 
test_prox 1 = [(0,[(0,0.2000),(1,0.2000),(2,0.2000),(3,0.0000),(4,0.2000),(5,0.2000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (1,[(0,0.2500),(1,0.2500),(2,0.0000),(3,0.2500),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.2500),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (2,[(0,0.1429),(1,0.0000),(2,0.1429),(3,0.1429),(4,0.1429),(5,0.1429),(6,0.1429),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.1429),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (3,[(0,0.0000),(1,0.1429),(2,0.1429),(3,0.1429),(4,0.1429),(5,0.1429),(6,0.1429),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.1429),(19,0.0000),(20,0.0000)])
     , (4,[(0,0.2000),(1,0.0000),(2,0.2000),(3,0.2000),(4,0.2000),(5,0.0000),(6,0.2000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (5,[(0,0.2000),(1,0.0000),(2,0.2000),(3,0.2000),(4,0.0000),(5,0.2000),(6,0.0000),(7,0.0000),(8,0.2000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (6,[(0,0.0000),(1,0.0000),(2,0.2500),(3,0.2500),(4,0.2500),(5,0.0000),(6,0.2500),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (7,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.2000),(8,0.2000),(9,0.2000),(10,0.2000),(11,0.0000),(12,0.0000),(13,0.2000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (8,[(0,0.0000),(1,0.1111),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.1111),(6,0.0000),(7,0.1111),(8,0.1111),(9,0.1111),(10,0.1111),(11,0.1111),(12,0.1111),(13,0.1111),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (9,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.2000),(8,0.2000),(9,0.2000),(10,0.0000),(11,0.0000),(12,0.2000),(13,0.2000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (10,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.2000),(8,0.2000),(9,0.0000),(10,0.2000),(11,0.2000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.2000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (11,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.2500),(9,0.0000),(10,0.2500),(11,0.2500),(12,0.2500),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (12,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.2500),(9,0.2500),(10,0.0000),(11,0.2500),(12,0.2500),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
     , (13,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.2000),(8,0.2000),(9,0.2000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.2000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.2000)])
     , (14,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.2000),(15,0.0000),(16,0.2000),(17,0.2000),(18,0.2000),(19,0.0000),(20,0.2000)])
     , (15,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.2000),(16,0.2000),(17,0.2000),(18,0.2000),(19,0.0000),(20,0.2000)])
     , (16,[(0,0.0000),(1,0.0000),(2,0.1667),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.1667),(15,0.1667),(16,0.1667),(17,0.0000),(18,0.1667),(19,0.0000),(20,0.1667)])
     , (17,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.1667),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.1667),(15,0.1667),(16,0.0000),(17,0.1667),(18,0.1667),(19,0.0000),(20,0.1667)])
     , (18,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.1250),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.1250),(15,0.1250),(16,0.1250),(17,0.1250),(18,0.1250),(19,0.1250),(20,0.1250)])
     , (19,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.3333),(19,0.3333),(20,0.3333)])
     , (20,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.1250),(14,0.1250),(15,0.1250),(16,0.1250),(17,0.1250),(18,0.1250),(19,0.1250),(20,0.1250)])
     ]


-- | longueur balade  2
test_prox 2 = [ (0,[(0,0.1986),(1,0.0900),(2,0.1486),(3,0.1586),(4,0.1086),(5,0.1086),(6,0.0686),(7,0.0000),(8,0.0900),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0286),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
   , (1,[(0,0.1125),(1,0.1760),(2,0.0857),(3,0.0982),(4,0.0857),(5,0.1135),(6,0.0357),(7,0.0278),(8,0.0903),(9,0.0278),(10,0.0278),(11,0.0278),(12,0.0278),(13,0.0278),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0357),(19,0.0000),(20,0.0000)])
   , (2,[(0,0.1061),(1,0.0490),(2,0.1861),(3,0.1337),(4,0.1337),(5,0.0980),(6,0.1051),(7,0.0000),(8,0.0286),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0238),(15,0.0238),(16,0.0442),(17,0.0000),(18,0.0442),(19,0.0000),(20,0.0238)])
   , (3,[(0,0.1133),(1,0.0561),(2,0.1337),(3,0.1872),(4,0.1051),(5,0.0694),(6,0.1051),(7,0.0000),(8,0.0643),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0179),(15,0.0179),(16,0.0383),(17,0.0179),(18,0.0383),(19,0.0179),(20,0.0179)])
   , (4,[(0,0.1086),(1,0.0686),(2,0.1871),(3,0.1471),(4,0.1871),(5,0.0971),(6,0.1471),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0286),(17,0.0000),(18,0.0286),(19,0.0000),(20,0.0000)])
   , (5,[(0,0.1086),(1,0.0908),(2,0.1371),(3,0.0971),(4,0.0971),(5,0.1594),(6,0.0571),(7,0.0222),(8,0.0622),(9,0.0222),(10,0.0222),(11,0.0222),(12,0.0222),(13,0.0222),(14,0.0000),(15,0.0000),(16,0.0286),(17,0.0000),(18,0.0286),(19,0.0000),(20,0.0000)])
   , (6,[(0,0.0857),(1,0.0357),(2,0.1839),(3,0.1839),(4,0.1839),(5,0.0714),(6,0.1839),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0000),(15,0.0000),(16,0.0357),(17,0.0000),(18,0.0357),(19,0.0000),(20,0.0000)])
   , (7,[(0,0.0000),(1,0.0222),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0222),(6,0.0000),(7,0.1822),(8,0.1822),(9,0.1422),(10,0.1022),(11,0.0622),(12,0.0622),(13,0.1422),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0400),(18,0.0000),(19,0.0000),(20,0.0400)])
   , (8,[(0,0.0500),(1,0.0401),(2,0.0222),(3,0.0500),(4,0.0000),(5,0.0346),(6,0.0000),(7,0.1012),(8,0.2068),(9,0.1068),(10,0.0846),(11,0.0901),(12,0.0901),(13,0.0790),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0222),(18,0.0000),(19,0.0000),(20,0.0222)])
   , (9,[(0,0.0000),(1,0.0222),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0222),(6,0.0000),(7,0.1422),(8,0.1922),(9,0.1922),(10,0.0622),(11,0.0722),(12,0.1122),(13,0.1422),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0400)])
   , (10,[(0,0.0000),(1,0.0222),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0222),(6,0.0000),(7,0.1022),(8,0.1522),(9,0.0622),(10,0.1856),(11,0.1122),(12,0.0722),(13,0.0622),(14,0.0333),(15,0.0333),(16,0.0000),(17,0.0733),(18,0.0333),(19,0.0000),(20,0.0333)])
   , (11,[(0,0.0000),(1,0.0278),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0278),(6,0.0000),(7,0.0778),(8,0.2028),(9,0.0903),(10,0.1403),(11,0.2028),(12,0.1528),(13,0.0278),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0500),(18,0.0000),(19,0.0000),(20,0.0000)])
   , (12,[(0,0.0000),(1,0.0278),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0278),(6,0.0000),(7,0.0778),(8,0.2028),(9,0.1403),(10,0.0903),(11,0.1528),(12,0.2028),(13,0.0778),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0000),(18,0.0000),(19,0.0000),(20,0.0000)])
   , (13,[(0,0.0000),(1,0.0222),(2,0.0000),(3,0.0000),(4,0.0000),(5,0.0222),(6,0.0000),(7,0.1422),(8,0.1422),(9,0.1422),(10,0.0622),(11,0.0222),(12,0.0622),(13,0.1672),(14,0.0250),(15,0.0250),(16,0.0250),(17,0.0250),(18,0.0250),(19,0.0250),(20,0.0650)])
   , (14,[(0,0.0000),(1,0.0000),(2,0.0333),(3,0.0250),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0333),(11,0.0000),(12,0.0000),(13,0.0250),(14,0.1567),(15,0.1167),(16,0.1233),(17,0.1233),(18,0.1567),(19,0.0500),(20,0.1567)])
   , (15,[(0,0.0000),(1,0.0000),(2,0.0333),(3,0.0250),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0333),(11,0.0000),(12,0.0000),(13,0.0250),(14,0.1167),(15,0.1567),(16,0.1233),(17,0.1233),(18,0.1567),(19,0.0500),(20,0.1567)])
   , (16,[(0,0.0238),(1,0.0000),(2,0.0516),(3,0.0446),(4,0.0238),(5,0.0238),(6,0.0238),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0208),(14,0.1028),(15,0.1028),(16,0.1599),(17,0.1083),(18,0.1361),(19,0.0417),(20,0.1361)])
   , (17,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0208),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0333),(8,0.0333),(9,0.0000),(10,0.0611),(11,0.0333),(12,0.0000),(13,0.0208),(14,0.1028),(15,0.1028),(16,0.1083),(17,0.1694),(18,0.1361),(19,0.0417),(20,0.1361)])
   , (18,[(0,0.0000),(1,0.0179),(2,0.0387),(3,0.0335),(4,0.0179),(5,0.0179),(6,0.0179),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0208),(11,0.0000),(12,0.0000),(13,0.0156),(14,0.0979),(15,0.0979),(16,0.1021),(17,0.1021),(18,0.1824),(19,0.0729),(20,0.1646)])
   , (19,[(0,0.0000),(1,0.0000),(2,0.0000),(3,0.0417),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0000),(8,0.0000),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0417),(14,0.0833),(15,0.0833),(16,0.0833),(17,0.0833),(18,0.1944),(19,0.1944),(20,0.1944)])
   , (20,[(0,0.0000),(1,0.0000),(2,0.0208),(3,0.0156),(4,0.0000),(5,0.0000),(6,0.0000),(7,0.0250),(8,0.0250),(9,0.0250),(10,0.0208),(11,0.0000),(12,0.0000),(13,0.0406),(14,0.0979),(15,0.0979),(16,0.1021),(17,0.1021),(18,0.1646),(19,0.0729),(20,0.1896)])
   ]

-- | longueur balade  3
test_prox 3 = [ (0,[(0,0.1269),(1,0.0949),(2,0.1489),(3,0.1269),(4,0.1224),(5,0.1153),(6,0.0827),(7,0.0100),(8,0.0542),(9,0.0100),(10,0.0100),(11,0.0100),(12,0.0100),(13,0.0100),(14,0.0048),(15,0.0048),(16,0.0260),(17,0.0000),(18,0.0274),(19,0.0000),(20,0.0048)])
   , (1,[(0,0.1186),(1,0.0906),(2,0.0975),(3,0.1235),(4,0.0748),(5,0.0815),(6,0.0523),(7,0.0323),(8,0.1128),(9,0.0336),(10,0.0281),(11,0.0295),(12,0.0295),(13,0.0267),(14,0.0045),(15,0.0045),(16,0.0167),(17,0.0100),(18,0.0185),(19,0.0045),(20,0.0100)])
   , (2,[(0,0.1064),(1,0.0557),(2,0.1469),(3,0.1360),(4,0.1199),(5,0.0897),(6,0.0987),(7,0.0032),(8,0.0350),(9,0.0032),(10,0.0032),(11,0.0032),(12,0.0032),(13,0.0062),(14,0.0206),(15,0.0206),(16,0.0520),(17,0.0180),(18,0.0445),(19,0.0085),(20,0.0254)])
   , (3,[(0,0.0907),(1,0.0706),(2,0.1360),(3,0.1258),(4,0.1158),(5,0.0895),(6,0.0931),(7,0.0071),(8,0.0351),(9,0.0071),(10,0.0101),(11,0.0071),(12,0.0071),(13,0.0094),(14,0.0199),(15,0.0199),(16,0.0396),(17,0.0171),(18,0.0562),(19,0.0130),(20,0.0295)])
   , (4,[(0,0.1224),(1,0.0599),(2,0.1679),(3,0.1621),(4,0.1437),(5,0.0889),(6,0.1220),(7,0.0000),(8,0.0366),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0083),(15,0.0083),(16,0.0351),(17,0.0036),(18,0.0294),(19,0.0036),(20,0.0083)])
   , (5,[(0,0.1153),(1,0.0652),(2,0.1255),(3,0.1253),(4,0.0889),(5,0.0940),(6,0.0672),(7,0.0247),(8,0.0904),(9,0.0258),(10,0.0214),(11,0.0225),(12,0.0225),(13,0.0202),(14,0.0083),(15,0.0083),(16,0.0279),(17,0.0080),(18,0.0222),(19,0.0036),(20,0.0128)])
   , (6,[(0,0.1034),(1,0.0523),(2,0.1727),(3,0.1630),(4,0.1525),(5,0.0840),(6,0.1353),(7,0.0000),(8,0.0232),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.0104),(15,0.0104),(16,0.0367),(17,0.0045),(18,0.0367),(19,0.0045),(20,0.0104)])
   , (7,[(0,0.0100),(1,0.0258),(2,0.0044),(3,0.0100),(4,0.0000),(5,0.0247),(6,0.0000),(7,0.1340),(8,0.1751),(9,0.1291),(10,0.0994),(11,0.0718),(12,0.0798),(13,0.1186),(14,0.0117),(15,0.0117),(16,0.0050),(17,0.0321),(18,0.0117),(19,0.0050),(20,0.0401)])
   , (8,[(0,0.0301),(1,0.0502),(2,0.0272),(3,0.0273),(4,0.0203),(5,0.0502),(6,0.0103),(7,0.0973),(8,0.1593),(9,0.1029),(10,0.0864),(11,0.0850),(12,0.0894),(13,0.0832),(14,0.0065),(15,0.0065),(16,0.0060),(17,0.0234),(18,0.0136),(19,0.0028),(20,0.0223)])
   , (9,[(0,0.0100),(1,0.0269),(2,0.0044),(3,0.0100),(4,0.0000),(5,0.0258),(6,0.0000),(7,0.1291),(8,0.1852),(9,0.1447),(10,0.0803),(11,0.0799),(12,0.1059),(13,0.1217),(14,0.0050),(15,0.0050),(16,0.0050),(17,0.0174),(18,0.0050),(19,0.0050),(20,0.0334)])
   , (10,[(0,0.0100),(1,0.0225),(2,0.0044),(3,0.0142),(4,0.0000),(5,0.0214),(6,0.0000),(7,0.0994),(8,0.1555),(9,0.0803),(10,0.1147),(11,0.1001),(12,0.0755),(13,0.0664),(14,0.0272),(15,0.0272),(16,0.0217),(17,0.0710),(18,0.0339),(19,0.0083),(20,0.0463)])
   , (11,[(0,0.0125),(1,0.0295),(2,0.0056),(3,0.0125),(4,0.0000),(5,0.0281),(6,0.0000),(7,0.0898),(8,0.1911),(9,0.0999),(10,0.1252),(11,0.1395),(12,0.1295),(13,0.0617),(14,0.0083),(15,0.0083),(16,0.0000),(17,0.0364),(18,0.0083),(19,0.0000),(20,0.0139)])
   , (12,[(0,0.0125),(1,0.0295),(2,0.0056),(3,0.0125),(4,0.0000),(5,0.0281),(6,0.0000),(7,0.0998),(8,0.2011),(9,0.1324),(10,0.0943),(11,0.1295),(12,0.1395),(13,0.0817),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.0181),(18,0.0000),(19,0.0000),(20,0.0156)])
   , (13,[(0,0.0100),(1,0.0214),(2,0.0086),(3,0.0131),(4,0.0000),(5,0.0202),(6,0.0000),(7,0.1186),(8,0.1497),(9,0.1217),(10,0.0664),(11,0.0494),(12,0.0654),(13,0.1143),(14,0.0246),(15,0.0246),(16,0.0254),(17,0.0379),(18,0.0379),(19,0.0196),(20,0.0714)])
   , (14,[(0,0.0048),(1,0.0036),(2,0.0289),(3,0.0279),(4,0.0083),(5,0.0083),(6,0.0083),(7,0.0117),(8,0.0117),(9,0.0050),(10,0.0272),(11,0.0067),(12,0.0000),(13,0.0246),(14,0.1116),(15,0.1036),(16,0.1192),(17,0.1211),(18,0.1552),(19,0.0558),(20,0.1566)])
   , (15,[(0,0.0048),(1,0.0036),(2,0.0289),(3,0.0279),(4,0.0083),(5,0.0083),(6,0.0083),(7,0.0117),(8,0.0117),(9,0.0050),(10,0.0272),(11,0.0067),(12,0.0000),(13,0.0246),(14,0.1036),(15,0.1116),(16,0.1192),(17,0.1211),(18,0.1552),(19,0.0558),(20,0.1566)])
   , (16,[(0,0.0217),(1,0.0111),(2,0.0606),(3,0.0462),(4,0.0292),(5,0.0233),(6,0.0245),(7,0.0042),(8,0.0089),(9,0.0042),(10,0.0181),(11,0.0000),(12,0.0000),(13,0.0212),(14,0.0993),(15,0.0993),(16,0.1092),(17,0.0932),(18,0.1401),(19,0.0479),(20,0.1379)])
   , (17,[(0,0.0000),(1,0.0067),(2,0.0210),(3,0.0200),(4,0.0030),(5,0.0067),(6,0.0030),(7,0.0268),(8,0.0351),(9,0.0145),(10,0.0592),(11,0.0243),(12,0.0120),(13,0.0316),(14,0.1009),(15,0.1009),(16,0.0932),(17,0.1156),(18,0.1383),(19,0.0479),(20,0.1395)])
   , (18,[(0,0.0171),(1,0.0092),(2,0.0389),(3,0.0492),(4,0.0183),(5,0.0139),(6,0.0183),(7,0.0073),(8,0.0153),(9,0.0031),(10,0.0212),(11,0.0042),(12,0.0000),(13,0.0237),(14,0.0970),(15,0.0970),(16,0.1051),(17,0.1037),(18,0.1457),(19,0.0677),(20,0.1440)])
   , (19,[(0,0.0000),(1,0.0060),(2,0.0198),(3,0.0303),(4,0.0060),(5,0.0060),(6,0.0060),(7,0.0083),(8,0.0083),(9,0.0083),(10,0.0139),(11,0.0000),(12,0.0000),(13,0.0326),(14,0.0931),(15,0.0931),(16,0.0958),(17,0.0958),(18,0.1805),(19,0.1134),(20,0.1829)])
   , (20,[(0,0.0030),(1,0.0050),(2,0.0222),(3,0.0258),(4,0.0052),(5,0.0080),(6,0.0052),(7,0.0251),(8,0.0251),(9,0.0209),(10,0.0290),(11,0.0069),(12,0.0078),(13,0.0446),(14,0.0979),(15,0.0979),(16,0.1034),(17,0.1046),(18,0.1440),(19,0.0686),(20,0.1499)])
   ]
test_prox _ = undefined


-- | confluence longueur balade 3
test_confluence_temoin :: Map Node (Map Node Double)
test_confluence_temoin = Map.map Map.fromList $ Map.fromList [(0,[(0,0.7448),(1,0.4844),(2,0.6471),(3,0.6759),(4,0.6297),(5,0.6219),(6,0.7040),(7,0.1870),(8,0.4092),(9,0.1870),(10,0.1870),(11,0.2233),(12,0.2233),(13,0.1870),(14,0.0987),(15,0.0987),(16,0.3325),(17,0.0000),(18,0.2827),(19,0.0000),(20,0.0641)])
   , (1,[(0,0.4844),(1,0.7225),(2,0.6158),(3,0.4509),(4,0.6326),(5,0.6521),(6,0.6008),(7,0.4259),(8,0.2441),(9,0.4362),(10,0.3925),(11,0.4587),(12,0.4587),(13,0.3804),(14,0.0931),(15,0.0931),(16,0.2426),(17,0.1611),(18,0.2100),(19,0.1461),(20,0.1259)])
   , (2,[(0,0.6471),(1,0.6158),(2,0.7070),(3,0.6569),(4,0.7060),(5,0.5915),(6,0.6918),(7,0.0680),(8,0.3091),(9,0.0680),(10,0.0680),(11,0.0836),(12,0.0836),(13,0.1239),(14,0.3219),(15,0.3219),(16,0.0630),(17,0.2568),(18,0.3901),(19,0.2458),(20,0.2674)])
   , (3,[(0,0.6759),(1,0.4509),(2,0.6569),(3,0.6740),(4,0.6865),(5,0.5777),(6,0.6659),(7,0.1411),(8,0.3093),(9,0.1411),(10,0.1888),(11,0.1704),(12,0.1704),(13,0.1774),(14,0.3144),(15,0.3144),(16,0.4317),(17,0.2472),(18,0.0602),(19,0.3320),(20,0.2975)])
   , (4,[(0,0.6297),(1,0.6326),(2,0.7060),(3,0.6865),(4,0.7677),(5,0.6716),(6,0.7228),(7,0.0000),(8,0.3185),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.1608),(15,0.1608),(16,0.4020),(17,0.0641),(18,0.2967),(19,0.1204),(20,0.1070)])
   , (5,[(0,0.6219),(1,0.6521),(2,0.5915),(3,0.5777),(4,0.6716),(5,0.6837),(6,0.6589),(7,0.3622),(8,0.2324),(9,0.3724),(10,0.3294),(11,0.3925),(12,0.3925),(13,0.3177),(14,0.1608),(15,0.1608),(16,0.3486),(17,0.1332),(18,0.2420),(19,0.1204),(20,0.1552)])
   , (6,[(0,0.7040),(1,0.6008),(2,0.6918),(3,0.6659),(4,0.7228),(5,0.6589),(6,0.7955),(7,0.0000),(8,0.2288),(9,0.0000),(10,0.0000),(11,0.0000),(12,0.0000),(13,0.0000),(14,0.1933),(15,0.1933),(16,0.4129),(17,0.0788),(18,0.3453),(19,0.1461),(20,0.1302)])
   , (7,[(0,0.1870),(1,0.4259),(2,0.0680),(3,0.1411),(4,0.0000),(5,0.3622),(6,0.0000),(7,0.7551),(8,0.6496),(9,0.6811),(10,0.4974),(11,0.6737),(12,0.6964),(13,0.6598),(14,0.2116),(15,0.2116),(16,0.0875),(17,0.3810),(18,0.1436),(19,0.1608),(20,0.3657)])
   , (8,[(0,0.4092),(1,0.2441),(2,0.3091),(3,0.3093),(4,0.3185),(5,0.2324),(6,0.2288),(7,0.6496),(8,0.6706),(9,0.6676),(10,0.5937),(11,0.6525),(12,0.6738),(13,0.5855),(14,0.1297),(15,0.1297),(16,0.1024),(17,0.3096),(18,0.1638),(19,0.0962),(20,0.2426)])
   , (9,[(0,0.1870),(1,0.4362),(2,0.0680),(3,0.1411),(4,0.0000),(5,0.3724),(6,0.0000),(7,0.6811),(8,0.6676),(9,0.7690),(10,0.6487),(11,0.6967),(12,0.5845),(13,0.6642),(14,0.1031),(15,0.1031),(16,0.0875),(17,0.2506),(18,0.0671),(19,0.1608),(20,0.3247)])
   , (10,[(0,0.1870),(1,0.3925),(2,0.0680),(3,0.1888),(4,0.0000),(5,0.3294),(6,0.0000),(7,0.4974),(8,0.5937),(9,0.6487),(10,0.7252),(11,0.5449),(12,0.6845),(13,0.6044),(14,0.3850),(15,0.3850),(16,0.2934),(17,0.0000),(18,0.3276),(19,0.2421),(20,0.3998)])
   , (11,[(0,0.2233),(1,0.4587),(2,0.0836),(3,0.1704),(4,0.0000),(5,0.3925),(6,0.0000),(7,0.6737),(8,0.6525),(9,0.6967),(10,0.5449),(11,0.8004),(12,0.6217),(13,0.5866),(14,0.1608),(15,0.1608),(16,0.0000),(17,0.4109),(18,0.1070),(19,0.0000),(20,0.1664)])
   , (12,[(0,0.2233),(1,0.4587),(2,0.0836),(3,0.1704),(4,0.0000),(5,0.3925),(6,0.0000),(7,0.6964),(8,0.6738),(9,0.5845),(10,0.6845),(11,0.6217),(12,0.8004),(13,0.6527),(14,0.0000),(15,0.0000),(16,0.0000),(17,0.2571),(18,0.0000),(19,0.0000),(20,0.1827)])
   , (13,[(0,0.1870),(1,0.3804),(2,0.1239),(3,0.1774),(4,0.0000),(5,0.3177),(6,0.0000),(7,0.6598),(8,0.5855),(9,0.6642),(10,0.6044),(11,0.5866),(12,0.6527),(13,0.7244),(14,0.3612),(15,0.3612),(16,0.3276),(17,0.4205),(18,0.3528),(19,0.4288),(20,0.0000)])
   , (14,[(0,0.0987),(1,0.0931),(2,0.3219),(3,0.3144),(4,0.1608),(5,0.1608),(6,0.1933),(7,0.2116),(8,0.1297),(9,0.1031),(10,0.3850),(11,0.1608),(12,0.0000),(13,0.3612),(14,0.7197),(15,0.7044),(16,0.6289),(17,0.6289),(18,0.6538),(19,0.6816),(20,0.6538)])
   , (15,[(0,0.0987),(1,0.0931),(2,0.3219),(3,0.3144),(4,0.1608),(5,0.1608),(6,0.1933),(7,0.2116),(8,0.1297),(9,0.1031),(10,0.3850),(11,0.1608),(12,0.0000),(13,0.3612),(14,0.7044),(15,0.7197),(16,0.6289),(17,0.6289),(18,0.6538),(19,0.6816),(20,0.6538)])
   , (16,[(0,0.3325),(1,0.2426),(2,0.0630),(3,0.4317),(4,0.4020),(5,0.3486),(6,0.4129),(7,0.0875),(8,0.1024),(9,0.0875),(10,0.2934),(11,0.0000),(12,0.0000),(13,0.3276),(14,0.6289),(15,0.6289),(16,0.6766),(17,0.6411),(18,0.6290),(19,0.6475),(20,0.6197)])
   , (17,[(0,0.0000),(1,0.1611),(2,0.2568),(3,0.2472),(4,0.0641),(5,0.1332),(6,0.0788),(7,0.3810),(8,0.3096),(9,0.2506),(10,0.0000),(11,0.4109),(12,0.2571),(13,0.4205),(14,0.6289),(15,0.6289),(16,0.6411),(17,0.6890),(18,0.6197),(19,0.6475),(20,0.6197)])
   , (18,[(0,0.2827),(1,0.2100),(2,0.3901),(3,0.0602),(4,0.2967),(5,0.2420),(6,0.3453),(7,0.1436),(8,0.1638),(9,0.0671),(10,0.3276),(11,0.1070),(12,0.0000),(13,0.3528),(14,0.6538),(15,0.6538),(16,0.6290),(17,0.6197),(18,0.6768),(19,0.6023),(20,0.6536)])
   , (19,[(0,0.0000),(1,0.1461),(2,0.2458),(3,0.3320),(4,0.1204),(5,0.1204),(6,0.1461),(7,0.1608),(8,0.0962),(9,0.1608),(10,0.2421),(11,0.0000),(12,0.0000),(13,0.4288),(14,0.6816),(15,0.6816),(16,0.6475),(17,0.6475),(18,0.6023),(19,0.8130),(20,0.6023)])
   , (20,[(0,0.0641),(1,0.1259),(2,0.2674),(3,0.2975),(4,0.1070),(5,0.1552),(6,0.1302),(7,0.3657),(8,0.2426),(9,0.3247),(10,0.3998),(11,0.1664),(12,0.1827),(13,0.0000),(14,0.6538),(15,0.6538),(16,0.6197),(17,0.6197),(18,0.6536),(19,0.6023),(20,0.6830)])
   ]
