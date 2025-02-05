{-|
Module      : Gargantext.API
Description : REST API declaration
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

Main (RESTful) API of the instance Gargantext.

The Garg-API is typed to derive the documentation, the mock and tests.

This API is indeed typed in order to be able to derive both the server
and the client sides.

The Garg-API-Monad enables:
  - Security (WIP)
  - Features (WIP)
  - Database connection (long term)
  - In Memory stack management (short term)
  - Logs (WIP)

Thanks to Yann Esposito for our discussions at the start and to Nicolas
Pouillard (who mainly made it).

-}

{-# LANGUAGE BangPatterns         #-}
{-# LANGUAGE NumericUnderscores   #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeOperators        #-}
module Gargantext.API
      where

import Control.Concurrent
import Control.Exception (catch, finally, SomeException{-, displayException, IOException-})
import Control.Lens
import Control.Monad.Except
import Control.Monad.Reader (runReaderT)
import Data.Either
import Data.Foldable (foldlM)
import Data.List (lookup)
import Data.Text (pack)
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO (putStrLn)
import Data.Validity
import GHC.Base (Applicative)
import GHC.Generics (Generic)
import Gargantext.API.Admin.Auth.Types (AuthContext)
import Gargantext.API.Admin.EnvTypes (Env)
import Gargantext.API.Admin.Settings (newEnv)
import Gargantext.API.Admin.Types (FireWall(..), PortNumber, cookieSettings, jwtSettings, settings)
import Gargantext.API.EKG
import Gargantext.API.Ngrams (saveNodeStoryImmediate)
import Gargantext.API.Routes
import Gargantext.API.Server (server)
import Gargantext.Core.NodeStory
-- import Gargantext.Database.Prelude (Cmd)
-- import Gargantext.Database.Action.Metrics.NgramsByContext (refreshNgramsMaterialized)
import Gargantext.Prelude hiding (putStrLn)
import Network.HTTP.Types hiding (Query)
import Network.Wai
import Network.Wai.Handler.Warp hiding (defaultSettings)
import Network.Wai.Middleware.Cors
import Network.Wai.Middleware.RequestLogger
import Paths_gargantext (getDataDir)
import Servant
import System.FilePath
import qualified Gargantext.Database.Prelude as DB
import qualified System.Cron.Schedule as Cron

data Mode = Dev | Mock | Prod
  deriving (Show, Read, Generic)

-- | startGargantext takes as parameters port number and Ini file.
startGargantext :: Mode -> PortNumber -> FilePath -> IO ()
startGargantext mode port file = do
  env <- newEnv port file
  runDbCheck env
  portRouteInfo port
  app <- makeApp env
  mid <- makeDevMiddleware mode
  periodicActions <- schedulePeriodicActions env
  run port (mid app) `finally` stopGargantext env periodicActions

  where runDbCheck env = do
          r <- runExceptT (runReaderT DB.dbCheck env) `catch`
            (\(_ :: SomeException) -> return $ Right False)
          case r of
            Right True -> return ()
            _ -> panic $
              "You must run 'gargantext-init " <> pack file <>
              "' before running gargantext-server (only the first time)."

portRouteInfo :: PortNumber -> IO ()
portRouteInfo port = do
  putStrLn "      ----Main Routes-----      "
  putStrLn $ "http://localhost:" <> toUrlPiece port <> "/index.html"
  putStrLn $ "http://localhost:" <> toUrlPiece port <> "/swagger-ui"

-- | Stops the gargantext server and cancels all the periodic actions
-- scheduled to run up to that point.
-- TODO clean this Monad condition (more generic) ?
stopGargantext :: HasNodeStoryImmediateSaver env => env -> [ThreadId] -> IO ()
stopGargantext env scheduledPeriodicActions = do
  forM_ scheduledPeriodicActions killThread
  putStrLn "----- Stopping gargantext -----"
  runReaderT saveNodeStoryImmediate env

{-
startGargantextMock :: PortNumber -> IO ()
startGargantextMock port = do
  portRouteInfo port
  application <- makeMockApp . MockEnv $ FireWall False
  run port application
-}

-- | Schedules all sorts of useful periodic actions to be run while
-- the server is alive accepting requests.
schedulePeriodicActions :: DB.CmdCommon env => env -> IO [ThreadId]
schedulePeriodicActions _env =
  -- Add your scheduled actions here.
  let actions = [
          -- refreshDBViews
        ]
  in foldlM (\ !acc action -> (`mappend` acc) <$> Cron.execSchedule action) [] actions

{-
  where

    refreshDBViews :: Cron.Schedule ()
    refreshDBViews = do
      let doRefresh = do
            res <- DB.runCmd env (refreshNgramsMaterialized :: Cmd IOException ())
            case res of
              Left e   -> liftIO $ putStrLn $ pack ("Refreshing Ngrams materialized view failed: " <> displayException e)
              Right () ->  do
                _ <- liftIO $ putStrLn $ pack "Refresh Index Database done"
                pure ()
      Cron.addJob doRefresh "* 2 * * *"
-}

----------------------------------------------------------------------

fireWall :: Applicative f => Request -> FireWall -> f Bool
fireWall req fw = do
    let origin = lookup "Origin" (requestHeaders req)
    let host   = lookup "Host"   (requestHeaders req)

    if  origin == Just (encodeUtf8 "http://localhost:8008")
       && host == Just (encodeUtf8 "localhost:3000")
       || (not $ unFireWall fw)

       then pure True
       else pure False

{-
-- makeMockApp :: Env -> IO (Warp.Settings, Application)
makeMockApp :: MockEnv -> IO Application
makeMockApp env = do
    let serverApp = appMock

    -- logWare <- mkRequestLogger def { destination = RequestLogger.Logger $ env^.logger }
    --logWare <- mkRequestLogger def { destination = RequestLogger.Logger "/tmp/logs.txt" }
    let checkOriginAndHost app req resp = do
            blocking <- fireWall req (env ^. menv_firewall)
            case blocking  of
                True  -> app req resp
                False -> resp ( responseLBS status401 []
                              "Invalid Origin or Host header")

    let corsMiddleware = cors $ \_ -> Just CorsResourcePolicy
--          { corsOrigins        = Just ([env^.settings.allowedOrigin], False)
            { corsOrigins        = Nothing --  == /*
            , corsMethods        = [ methodGet   , methodPost   , methodPut
                                   , methodDelete, methodOptions, methodHead]
            , corsRequestHeaders = ["authorization", "content-type"]
            , corsExposedHeaders = Nothing
            , corsMaxAge         = Just ( 60*60*24 ) -- one day
            , corsVaryOrigin     = False
            , corsRequireOrigin  = False
            , corsIgnoreFailures = False
            }

    --let warpS = Warp.setPort (8008 :: Int)   -- (env^.settings.appPort)
    --          $ Warp.defaultSettings

    --pure (warpS, logWare $ checkOriginAndHost $ corsMiddleware $ serverApp)
    pure $ logStdoutDev $ checkOriginAndHost $ corsMiddleware $ serverApp
-}


makeDevMiddleware :: Mode -> IO Middleware
makeDevMiddleware mode = do
-- logWare <- mkRequestLogger def { destination = RequestLogger.Logger $ env^.logger }
-- logWare <- mkRequestLogger def { destination = RequestLogger.Logger "/tmp/logs.txt" }
--    let checkOriginAndHost app req resp = do
--            blocking <- fireWall req (env ^. menv_firewall)
--            case blocking  of
--                True  -> app req resp
--                False -> resp ( responseLBS status401 []
--                              "Invalid Origin or Host header")
--
    let corsMiddleware = cors $ \_ -> Just CorsResourcePolicy
--          { corsOrigins        = Just ([env^.settings.allowedOrigin], False)
            { corsOrigins        = Nothing --  == /*
            , corsMethods        = [ methodGet   , methodPost   , methodPut
                                   , methodDelete, methodOptions, methodHead]
            , corsRequestHeaders = ["authorization", "content-type"]
            , corsExposedHeaders = Nothing
            , corsMaxAge         = Just ( 60*60*24 ) -- one day
            , corsVaryOrigin     = False
            , corsRequireOrigin  = False
            , corsIgnoreFailures = False
            }

    --let warpS = Warp.setPort (8008 :: Int)   -- (env^.settings.appPort)
    --          $ Warp.defaultSettings

    --pure (warpS, logWare . checkOriginAndHost . corsMiddleware)
    case mode of
      Prod -> pure $ logStdout . corsMiddleware
      _    -> pure $ logStdoutDev . corsMiddleware

---------------------------------------------------------------------
-- | API Global
---------------------------------------------------------------------

---------------------------


-- TODO-SECURITY admin only: withAdmin
-- Question: How do we mark admins?
{-
serverGargAdminAPI :: GargServer GargAdminAPI
serverGargAdminAPI =  roots
                 :<|> nodesAPI
-}

---------------------------------------------------------------------
--gargMock :: Server GargAPI
--gargMock = mock apiGarg Proxy
---------------------------------------------------------------------

makeApp :: Env -> IO Application
makeApp env = do
  serv <- server env
  (ekgStore, ekgMid) <- newEkgStore api
  ekgDir <- (</> "ekg-assets") <$> getDataDir
  return $ ekgMid $ serveWithContext apiWithEkg cfg
    (ekgServer ekgDir ekgStore :<|> serv)
  where
    cfg :: Servant.Context AuthContext
    cfg = env ^. settings . jwtSettings
       :. env ^. settings . cookieSettings
    -- :. authCheck env
       :. EmptyContext

--appMock :: Application
--appMock = serve api (swaggerFront :<|> gargMock :<|> serverStatic)
---------------------------------------------------------------------
api :: Proxy API
api  = Proxy

apiWithEkg :: Proxy (EkgAPI :<|> API)
apiWithEkg = Proxy

apiGarg :: Proxy GargAPI
apiGarg  = Proxy
---------------------------------------------------------------------

{- UNUSED
--import GHC.Generics (D1, Meta (..), Rep, Generic)
--import GHC.TypeLits (AppendSymbol, Symbol)
---------------------------------------------------------------------
-- Type Family for the Documentation
type family TypeName (x :: *) :: Symbol where
    TypeName Int  = "Int"
    TypeName Text = "Text"
    TypeName x    = GenericTypeName x (Rep x ())

type family GenericTypeName t (r :: *) :: Symbol where
    GenericTypeName t (D1 ('MetaData name mod pkg nt) f x) = name

type Desc t n = Description (AppendSymbol (TypeName t) (AppendSymbol " | " n))
-}
