{-|
Module      : Gargantext.Database.Root
Description : Main requests to get root of users
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX
-}

{-# LANGUAGE Arrows #-}

module Gargantext.Database.Query.Tree.Root
  where

import Control.Arrow (returnA)
import Data.Either (Either, fromLeft, fromRight)
import Gargantext.Core
import Gargantext.Core.Types.Individu (User(..))
import Gargantext.Core.Types.Main (CorpusName)
import Gargantext.Database.Action.Node
import Gargantext.Database.Action.User (getUserId, getUsername)
import Gargantext.Database.Admin.Config
import Gargantext.Database.Admin.Types.Hyperdata (HyperdataUser)
import Gargantext.Database.Admin.Types.Node
import Gargantext.Database.Prelude (Cmd, runOpaQuery)
import Gargantext.Database.Query.Table.Node
import Gargantext.Database.Query.Table.Node.Error
import Gargantext.Database.Query.Table.User (queryUserTable, UserPoly(..))
import Gargantext.Database.Schema.Node (NodePoly(..), NodeRead)
import Gargantext.Database.Schema.Node (queryNodeTable)
import Gargantext.Prelude
import Opaleye (restrict, (.==), Select)
import Opaleye.SqlTypes (sqlStrictText, sqlInt4)


getRootId :: (HasNodeError err) => User -> Cmd err NodeId
getRootId u = do
  maybeRoot <- head <$> getRoot u
  case maybeRoot of
    Nothing -> nodeError $ NodeError "[G.D.Q.T.R.getRootId] No root id"
    Just  r -> pure (_node_id r)

getRoot :: User -> Cmd err [Node HyperdataUser]
getRoot = runOpaQuery . selectRoot

getOrMkRoot :: (HasNodeError err)
            => User
            -> Cmd err (UserId, RootId)
getOrMkRoot user = do
  userId <- getUserId user

  rootId' <- map _node_id <$> getRoot user

  rootId'' <- case rootId' of
        []  -> mkRoot user
        n   -> case length n >= 2 of
            True  -> nodeError ManyNodeUsers
            False -> pure rootId'

  rootId <- maybe (nodeError NoRootFound) pure (head rootId'')
  pure (userId, rootId)


getOrMk_RootWithCorpus :: (HasNodeError err, MkCorpus a)
                      => User
                      -> Either CorpusName [CorpusId]
                      -> Maybe a
                      -> Cmd err (UserId, RootId, CorpusId)
getOrMk_RootWithCorpus user cName c = do
  (userId, rootId) <- getOrMkRoot user
  corpusId'' <- if user == UserName userMaster
                  then do
                    ns <- getCorporaWithParentId rootId
                    pure $ map _node_id ns
                  else
                    pure $ fromRight [] cName

  corpusId' <- if corpusId'' /= []
                  then pure corpusId''
                  else do
                    c' <- mk (Just $ fromLeft "Default" cName) c rootId userId
                    _tId <- case head c' of
                              Nothing  -> nodeError $ NodeError "[G.D.Q.T.Root.getOrMk...] mk Corpus failed"
                              Just c'' -> insertDefaultNode NodeTexts c'' userId
                    pure c'

  corpusId <- maybe (nodeError NoCorpusFound) pure (head corpusId')
  pure (userId, rootId, corpusId)


mkRoot :: HasNodeError err
       => User
       -> Cmd err [RootId]
mkRoot user = do

  -- TODO
  -- udb <- getUserDb user
  -- let uid = user_id udb
  uid <- getUserId user

  -- TODO ? Which name for user Node ?
  una <- getUsername user

  case uid > 0 of
     False -> nodeError NegativeId
     True  -> do
       rs <- mkNodeWithParent NodeUser Nothing uid una
       _ <- case rs of
         [r] -> do
           _ <- insertNode NodeFolderPrivate Nothing Nothing r uid
           _ <- insertNode NodeFolderShared Nothing Nothing r uid
           _ <- insertNode NodeFolderPublic Nothing Nothing r uid
           pure rs
         _   -> pure rs
       pure rs

selectRoot :: User -> Select NodeRead
selectRoot (UserName username) = proc () -> do
    row   <- queryNodeTable -< ()
    users <- queryUserTable -< ()
    restrict -< _node_typename row   .== (sqlInt4 $ toDBid NodeUser)
    restrict -< user_username  users .== (sqlStrictText username)
    restrict -< _node_user_id   row   .== (user_id users)
    returnA  -< row

selectRoot (UserDBId uid) = proc () -> do
    row   <- queryNodeTable -< ()
    restrict -< _node_typename row   .== (sqlInt4 $ toDBid NodeUser)
    restrict -< _node_user_id   row   .== (sqlInt4 uid)
    returnA  -< row

selectRoot (RootId nid) =
 proc () -> do
    row   <- queryNodeTable -< ()
    restrict -< _node_typename row   .== (sqlInt4 $ toDBid NodeUser)
    restrict -< _node_id   row   .== (pgNodeId nid)
    returnA  -< row
selectRoot UserPublic = panic {-nodeError $ NodeError-}  "[G.D.Q.T.Root.selectRoot] No root for Public"
