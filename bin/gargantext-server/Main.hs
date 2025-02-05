{-|
Module      : Main.hs
Description : Gargantext starter
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

Script to start gargantext with different modes (Dev, Prod, Mock).

-}

{-# LANGUAGE QuasiQuotes          #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE Strict               #-}
{-# LANGUAGE TypeOperators        #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}


module Main where


import Data.Maybe (fromMaybe)
import Data.Text (unpack)
import Data.Version (showVersion)
import Database.PostgreSQL.Simple.SqlQQ (sql)
import GHC.IO.Exception (IOException)
import Gargantext.API (startGargantext, Mode(..)) -- , startGargantextMock)
import Gargantext.API.Admin.EnvTypes (DevEnv)
import Gargantext.API.Dev (withDevEnv, runCmdDev)
import Gargantext.Prelude
import Options.Generic
import System.Exit (exitSuccess)
import qualified Paths_gargantext as PG -- cabal magic build module


instance ParseRecord Mode
instance ParseField  Mode
instance ParseFields Mode

data MyOptions w =
  MyOptions { run  :: w ::: Mode
                        <?> "Possible modes: Dev | Mock | Prod"
            , port :: w ::: Maybe Int
                        <?> "By default: 8008"
            , ini  :: w ::: Maybe Text
                        <?> "Ini-file path of gargantext.ini"
            , version :: w ::: Bool
                        <?> "Show version number and exit"
            }
   deriving (Generic)

instance ParseRecord (MyOptions Wrapped)
deriving instance Show (MyOptions Unwrapped)


main :: IO ()
main = do
  MyOptions myMode myPort myIniFile myVersion  <- unwrapRecord
          "Gargantext server"
  ---------------------------------------------------------------
  if myVersion then do
    putStrLn $ "Version: " <> showVersion PG.version
    System.Exit.exitSuccess
  else
    return ()
  ---------------------------------------------------------------
  let myPort' = case myPort of
        Just p  -> p
        Nothing -> 8008

      myIniFile' = case myIniFile of
          Nothing -> panic "[ERROR] gargantext.ini needed"
          Just i  -> i

  ---------------------------------------------------------------
  let start = case myMode of
        Mock -> panic "[ERROR] Mock mode unsupported"
        _ -> startGargantext myMode myPort' (unpack myIniFile')
  putStrLn $ "Starting with " <> show myMode <> " mode."
  start
  ---------------------------------------------------------------
