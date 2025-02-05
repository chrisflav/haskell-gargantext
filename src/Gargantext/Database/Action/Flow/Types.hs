{-|
Module      : Gargantext.Database.Flow.Types
Description : Types for Flow
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# OPTIONS_GHC -fno-warn-orphans    #-}

{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE ConstrainedClassMethods #-}
{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE InstanceSigs            #-}

module Gargantext.Database.Action.Flow.Types
    where

import Data.Aeson (ToJSON)

import Gargantext.Core.Types (HasInvalidError)
import Gargantext.Core.Flow.Types
import Gargantext.Core.Text
import Gargantext.Core.NodeStory
import Gargantext.Core.Text.Terms
import Gargantext.Database.Query.Table.Node.Error (HasNodeError)
import Gargantext.Database.Prelude (CmdM)
import Gargantext.Database.Query.Table.Node.Document.Insert
import Gargantext.Database.Query.Tree.Error (HasTreeError)

type FlowCmdM env err m =
  ( CmdM     env err m
  , HasNodeStory env err m
  , HasNodeError err
  , HasInvalidError err
  , HasTreeError err
  )

type FlowCorpus a = ( AddUniqId      a
                    , UniqId         a
                    , UniqParameters a
                    , InsertDb       a
                    , ExtractNgramsT a
                    , HasText        a
                    , ToNode         a
                    , ToJSON         a
                    )

type FlowInsertDB a = ( AddUniqId a
                      , UniqId    a
                      , UniqParameters a
                      , InsertDb  a
                      )
