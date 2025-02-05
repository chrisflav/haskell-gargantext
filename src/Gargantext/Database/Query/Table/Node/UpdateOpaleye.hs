{-|
Module      : Gargantext.Database.Node.UpdateOpaleye
Description : Update Node in Database (Postgres)
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# LANGUAGE QuasiQuotes       #-}


module Gargantext.Database.Query.Table.Node.UpdateOpaleye
  where

import Opaleye
import Data.Aeson (encode, ToJSON)
import Gargantext.Core
import Gargantext.Prelude
import Gargantext.Database.Schema.Node
import Gargantext.Database.Admin.Types.Node
import Gargantext.Database.Prelude (Cmd, mkCmd, JSONB)
import Gargantext.Database.Query.Table.Node
import Gargantext.Database.Query.Table.Node.Error

import Debug.Trace (trace)

updateHyperdata :: ToJSON a => NodeId -> a -> Cmd err Int64
updateHyperdata i h = mkCmd $ \c -> putStrLn "before runUpdate_" >>
                                    runUpdate_ c (updateHyperdataQuery i h) >>= \res ->
                                    putStrLn "after runUpdate_" >> return res

updateHyperdataQuery :: ToJSON a => NodeId -> a -> Update Int64
updateHyperdataQuery i h = seq h' $ trace "updateHyperdataQuery: encoded JSON" $ Update
   { uTable      = nodeTable
   , uUpdateWith = updateEasy (\  (Node { .. })
                                -> Node { _node_hyperdata = h', .. }
                               -- -> trace "updating mate" $ Node _ni _nh _nt _nu _np _nn _nd h'
                              )
   , uWhere      = (\row -> {-trace "uWhere" $-} _node_id row .== pgNodeId i )
   , uReturning  = rCount
   }
    where h' =  (sqlJSONB $ cs $ encode $ h)

----------------------------------------------------------------------------------
updateNodesWithType :: ( HasNodeError err
                       , JSONB a
                       , ToJSON a
                       , HasDBid NodeType
                       ) => NodeType -> proxy a -> (a -> a) -> Cmd err [Int64]
updateNodesWithType nt p f = do
  ns <- getNodesWithType nt p
  mapM (\n -> updateHyperdata (_node_id n) (f $ _node_hyperdata n)) ns


-- | In case the Hyperdata Types are not compatible
updateNodesWithType_ :: ( HasNodeError err
                        , JSONB a
                        , ToJSON a
                        , HasDBid NodeType
                        ) => NodeType -> a -> Cmd err [Int64]
updateNodesWithType_ nt h = do
  ns <- getNodesIdWithType nt
  mapM (\n -> updateHyperdata n h) ns
