{-|
Module      : Gargantext.Viz.Phylo.Tools
Description : Phylomemy Tools to build/manage it
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}


{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}   -- allows to write Text literals
{-# LANGUAGE OverloadedLists   #-}   -- allows to write Map and HashMap as lists
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE TypeOperators      #-}

module Gargantext.Viz.Graph.API
  where

import Data.List (sortOn)
import Control.Lens (set, view)
import Control.Monad.IO.Class (liftIO)
import Gargantext.API.Ngrams.Tools
import Gargantext.API.Types
import Gargantext.Core.Types.Main
import Gargantext.Database.Metrics.NgramsByNode (getNodesByNgramsOnlyUser)
import Gargantext.Database.Schema.Ngrams
import Gargantext.Database.Schema.Node (getNode)
import Gargantext.Database.Schema.Node (defaultList)
import Gargantext.Database.Types.Node hiding (node_id) -- (GraphId, ListId, CorpusId, NodeId)
import Gargantext.Prelude
import Gargantext.Viz.Graph
import Gargantext.Viz.Graph.Tools -- (cooc2graph)
import Servant
import qualified Data.Map as Map

------------------------------------------------------------------------

-- | There is no Delete specific API for Graph since it can be deleted
-- as simple Node.
type GraphAPI   =  Get  '[JSON] Graph
              :<|> Post '[JSON] [GraphId]
              :<|> Put  '[JSON] Int


graphAPI :: NodeId -> GargServer GraphAPI
graphAPI n =  getGraph  n
         :<|> postGraph n
         :<|> putGraph  n

------------------------------------------------------------------------

getGraph :: NodeId -> GargServer (Get '[JSON] Graph)
getGraph nId = do
  nodeGraph <- getNode nId HyperdataGraph

  let metadata = GraphMetadata "Title" [maybe 0 identity $ _node_parentId nodeGraph]
                                     [ LegendField 1 "#FFF" "Cluster"
                                     , LegendField 2 "#FFF" "Cluster"
                                     ]
                         -- (map (\n -> LegendField n "#FFFFFF" (pack $ show n)) [1..10])
  let cId = maybe (panic "no parentId") identity $ _node_parentId nodeGraph

  lId <- defaultList cId
  ngs    <- filterListWithRoot GraphTerm <$> mapTermListRoot [lId] NgramsTerms

  myCooc <- Map.filter (>1) <$> getCoocByNgrams (Diagonal False)
                            <$> groupNodesByNgrams ngs
                            <$> getNodesByNgramsOnlyUser cId NgramsTerms (Map.keys ngs)

  graph <- liftIO $ cooc2graph myCooc
  pure $ set graph_metadata (Just metadata)
       $ set graph_nodes ( sortOn node_id
                         $ view graph_nodes graph
                         ) graph


postGraph :: NodeId -> GargServer (Post '[JSON] [NodeId])
postGraph = undefined

putGraph :: NodeId -> GargServer (Put '[JSON] Int)
putGraph = undefined




-- | Instances

