{-|
Module      : Gargantext.Database.Action.User
Description :
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX
-}

{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# OPTIONS_GHC -fno-warn-orphans        #-}

module Gargantext.Database.Action.User
  where

-- import Data.Maybe (catMaybes)
import Data.Text (Text, unlines, splitOn)
import Gargantext.Database.Query.Table.User
import Gargantext.Core.Types.Individu
import Gargantext.Database.Prelude
import Control.Monad.Random
import Gargantext.Prelude
import Gargantext.Prelude.Mail (gargMail, GargMail(..))
import Gargantext.Database.Query.Table.Node.Error (HasNodeError(..), nodeError, NodeError(..))
import Gargantext.Database.Action.Flow (getOrMkRoot)
import Gargantext.Prelude.Crypto.Pass.User (gargPass)

type EmailAddress = Text

------------------------------------------------------------------------
newUsers :: (CmdM env err m, MonadRandom m, HasNodeError err) => Text -> [Text] -> m Int64
newUsers address us = do
  us' <- mapM newUserQuick us
  newUsers' address us'
------------------------------------------------------------------------
newUserQuick :: (MonadRandom m) => Text -> m (NewUser GargPassword)
newUserQuick n = do
  pass <- gargPass
  let (u,_m) = guessUserName n
  pure (NewUser u n (GargPassword pass))

-- | TODO better check for invalid email adress
guessUserName :: Text -> (Text,Text)
guessUserName n = case splitOn "@" n of
    [u',m'] -> if m' /= "" then (u',m')
                           else panic "Email Invalid"
    _  -> panic "Email invalid"

------------------------------------------------------------------------
newUser' :: HasNodeError err
        => Text -> NewUser GargPassword -> Cmd err Int64
newUser' address u = newUsers' address [u]

newUsers' :: HasNodeError err
         => Text -> [NewUser GargPassword] -> Cmd err Int64
newUsers' address us = do
  us' <- liftBase    $ mapM toUserHash us
  r   <- insertUsers $ map toUserWrite us'
  _   <- mapM getOrMkRoot $ map (\u -> UserName (_nu_username u)) us
  _   <- liftBase    $ mapM (mail Invitation address) us
  pure r
------------------------------------------------------------------------
updateUser :: HasNodeError err
           => Text -> NewUser GargPassword -> Cmd err Int64
updateUser address u = do
  u' <- liftBase   $ toUserHash   u
  n  <- updateUserDB $ toUserWrite  u'
  _  <- liftBase   $ mail Update address u
  pure n

------------------------------------------------------------------------
data Mail = Invitation
          | Update


-- TODO gargantext.ini config
mail :: Mail -> Text -> NewUser GargPassword -> IO ()
mail mtype address nu@(NewUser u m _) = gargMail (GargMail m (Just u) subject body)
  where
    subject = "[Your Garg Account]"
    body    = bodyWith mtype address nu

bodyWith :: Mail -> Text -> NewUser GargPassword -> Text
bodyWith Invitation add nu = logInstructions    add nu
bodyWith Update     add nu = updateInstructions add nu


-- TODO put this in a configurable file (path in gargantext.ini)
logInstructions :: Text -> NewUser GargPassword -> Text
logInstructions address (NewUser u _ (GargPassword p)) =
  unlines [ "Hello"
          , "You have been invited to test the new GarganText platform!"
          , ""
          , "You can log in to: " <> address
          , "Your username is: "  <> u
          , "Your password is: "  <> p
          , ""
          , "Please read the full terms of use on:"
          , "https://gitlab.iscpif.fr/humanities/tofu/tree/master"
          , ""
          , "Your feedback will be valuable for further development"
          , "of the platform, do not hesitate to contact us and"
          , "to contribute on our forum:"
          , "     https://discourse.iscpif.fr/c/gargantext"
          , ""
          , "With our best regards,"
          , "-- "
          , "The Gargantext Team (CNRS)"
          ]

updateInstructions :: Text -> NewUser GargPassword -> Text
updateInstructions address (NewUser u _ (GargPassword p)) =
  unlines [ "Hello"
          , "Your account have been updated on the GarganText platform!"
          , ""
          , "You can log in to: " <> address
          , "Your username is: "  <> u
          , "Your password is: "  <> p
          , ""
          , "As reminder, please read the full terms of use on:"
          , "https://gitlab.iscpif.fr/humanities/tofu/tree/master"
          , ""
          , "Your feedback is always valuable for further development"
          , "of the platform, do not hesitate to contact us and"
          , "to contribute on our forum:"
          , "     https://discourse.iscpif.fr/c/gargantext"
          , ""
          , "With our best regards,"
          , "-- "
          , "The Gargantext Team (CNRS)"
          ]


------------------------------------------------------------------------
rmUser :: HasNodeError err => User -> Cmd err Int64
rmUser (UserName un) = deleteUsers [un]
rmUser _ = nodeError NotImplYet

-- TODO
rmUsers :: HasNodeError err => [User] -> Cmd err Int64
rmUsers [] = pure 0
rmUsers _  = undefined
