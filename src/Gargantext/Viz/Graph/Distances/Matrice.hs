{-|
Module      : Gargantext.Graph.Distances.Matrix
Description : 
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

Motivation and definition of the @Conditional@ distance.

Implementation use Accelerate library :
  * Manuel M. T. Chakravarty, Gabriele Keller, Sean Lee, Trevor L. McDonell, and Vinod Grover.
    [Accelerating Haskell Array Codes with Multicore GPUs][CKLM+11].
    In _DAMP '11: Declarative Aspects of Multicore Programming_, ACM, 2011.

  * Trevor L. McDonell, Manuel M. T. Chakravarty, Gabriele Keller, and Ben Lippmeier.
    [Optimising Purely Functional GPU Programs][MCKL13].
    In _ICFP '13: The 18th ACM SIGPLAN International Conference on Functional Programming_, ACM, 2013.

  * Robert Clifton-Everest, Trevor L. McDonell, Manuel M. T. Chakravarty, and Gabriele Keller.
    [Embedding Foreign Code][CMCK14].
    In _PADL '14: The 16th International Symposium on Practical Aspects of Declarative Languages_, Springer-Verlag, LNCS, 2014.

  * Trevor L. McDonell, Manuel M. T. Chakravarty, Vinod Grover, and Ryan R. Newton.
    [Type-safe Runtime Code Generation: Accelerate to LLVM][MCGN15].
    In _Haskell '15: The 8th ACM SIGPLAN Symposium on Haskell_, ACM, 2015.

-}

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE TypeOperators     #-}

module Gargantext.Viz.Graph.Distances.Matrice
  where

import Data.Array.Accelerate
import Data.Array.Accelerate.Interpreter (run)
import Data.Array.Accelerate.Smart
import Data.Array.Accelerate.Type
import Data.Array.Accelerate.Array.Sugar (fromArr, Array, Z)

import Data.Maybe (Maybe(Just))
import qualified Gargantext.Prelude as P
import qualified Data.Array.Accelerate.Array.Representation     as Repr

import Gargantext.Text.Metrics.Occurrences


-----------------------------------------------------------------------
-- Test perf.
distriTest = distributional $ myMat 100
-----------------------------------------------------------------------

vector :: Int -> (Array (Z :. Int) Int)
vector n = fromList (Z :. n) [0..n]

matrix :: Elt c => Int -> [c] -> Matrix c
matrix n l = fromList (Z :. n :. n) l

myMat :: Int -> Matrix Int
myMat n = matrix n [1..]

-- | Two ways to get the rank (as documentation)
rank :: (Matrix a) -> Int
rank m = arrayRank $ arrayShape m

rank' :: (Matrix a) -> Int
rank' m = n
  where
    Z :. _ :. n = arrayShape m

-----------------------------------------------------------------------
-- | Conditional Distance

type Rank = Int

proba :: Rank -> Acc (Matrix Double) -> Acc (Matrix Double)
proba r mat = zipWith (/) mat (mkSum r mat)

mkSum :: Rank -> Acc (Matrix Double) -> Acc (Matrix Double)
mkSum r mat = replicate (constant (Z :. (r :: Int) :. All)) 
            $ fold (+) 0 mat


type Matrix' a = Acc (Matrix a)
type InclusionExclusion    = Double
type SpecificityGenericity = Double


miniMax :: Matrix' Double -> Matrix' Double
miniMax m = map (\x -> ifThenElse (x > miniMax') x 0) m
  where
    miniMax' = (the $ minimum $ maximum m)

conditional :: Matrix Int -> Matrix Double
conditional m = run (miniMax $ proba r $ map fromIntegral $ use m)
  where
    r :: Rank
    r = rank' m


conditional' :: Matrix Double -> (Matrix InclusionExclusion, Matrix SpecificityGenericity)
conditional' m = (run $ ie (use m), run $ sg (use m))
  where

    ie :: Matrix' Double -> Matrix' Double
    ie mat = map (\x -> x / (2*n-1)) $ zipWith (+) (xs mat) (ys mat)
    sg :: Acc (Matrix Double) -> Acc (Matrix Double)
    sg mat = map (\x -> x / (2*n-1)) $ zipWith (-) (xs mat) (ys mat)

    n :: Exp Double
    n = P.fromIntegral r

    r :: Rank
    r = rank' m

    xs :: Matrix' Double -> Matrix' Double
    xs mat = zipWith (-) (proba r mat) (mkSum r $ proba r mat)
    ys :: Acc (Matrix Double) -> Acc (Matrix Double)
    ys mat = zipWith (-) (proba r mat) (mkSum r $ transpose $ proba r mat)

-- filter with threshold
-----------------------------------------------------------------------

-- | Distributional Distance

distributional :: Matrix Int -> Matrix Double
distributional m = run $ miniMax $ ri (map fromIntegral $ use m)
  where
    n    = rank' m
    
    filter  m = zipWith (\a b -> max a b) m (transpose m)
    
    ri mat = zipWith (/) mat1 mat2
      where
        mat1 = mkSum n $ zipWith min (mi mat) (mi $ transpose mat)
        mat2 = mkSum n mat
    
    mi    m'  = zipWith (\a b -> max (log $ a/b) 0)  m'
              $ zipWith (/) (crossProduct m') (total m')

    total m'' = replicate (constant (Z :. n :. n)) $ fold (+) 0 $ fold (+) 0 m''
    
    crossProduct m = zipWith (*) (cross m  ) (cross (transpose m))
    cross mat      = zipWith (-) (mkSum n mat) (mat)


int2double :: Matrix Int -> Matrix Double
int2double m = run (map fromIntegral $ use m)

