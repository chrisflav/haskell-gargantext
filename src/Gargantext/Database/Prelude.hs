{-|
Module      : Gargantext.Database.Prelude
Description : Specific Prelude for Database management
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

{-# LANGUAGE Arrows #-}
{-# LANGUAGE ConstraintKinds, ScopedTypeVariables #-}
{-# LANGUAGE LambdaCase #-}

module Gargantext.Database.Prelude where

--import Control.Monad.Logger (MonadLogger)
import Control.Exception
import Control.Lens (Getter, view)
import Control.Monad.Except
import Control.Monad.Random
import Control.Monad.Reader
import Control.Monad.Trans.Control (MonadBaseControl)
import Data.Aeson (Result(Error,Success), fromJSON, FromJSON)
import Data.ByteString.Char8 (hPutStrLn)
import Data.Either.Extra (Either)
import Data.Pool (Pool, withResource)
import Data.Profunctor.Product.Default (Default)
import Data.Text (pack, unpack, Text)
import Data.Word (Word16)
import Database.PostgreSQL.Simple (Connection, connect)
import Database.PostgreSQL.Simple.FromField ( Conversion, ResultError(ConversionFailed), fromField, returnError)
import Database.PostgreSQL.Simple.Internal  (Field)
import Database.PostgreSQL.Simple.Types (Query(..))
import Gargantext.Core.Mail.Types (HasMail)
import Gargantext.Core.NLP (HasNLPServer)
import Gargantext.Prelude
import Gargantext.Prelude.Config (GargConfig(), readIniFile', val)
import Opaleye (Unpackspec, showSql, FromFields, Select, runSelect, SqlJsonb, DefaultFromField, toFields, matchMaybe, MaybeFields)
import Opaleye.Aggregate (countRows)
import System.IO (FilePath, stderr)
import Text.Read (readMaybe)
import qualified Data.ByteString      as DB
import qualified Data.List as DL
import qualified Database.PostgreSQL.Simple as PGS
import qualified Opaleye.Internal.Constant
import qualified Opaleye.Internal.Operators

-------------------------------------------------------
class HasConnectionPool env where
  connPool :: Getter env (Pool Connection)

instance HasConnectionPool (Pool Connection) where
  connPool = identity

class HasConfig env where
  hasConfig :: Getter env GargConfig

instance HasConfig GargConfig where
  hasConfig = identity

-------------------------------------------------------
type JSONB = DefaultFromField SqlJsonb
-------------------------------------------------------

type CmdM'' env err m =
  ( MonadReader     env     m
  , MonadError          err m
  , MonadBaseControl IO     m
  , MonadRandom             m
  --, MonadLogger             m
  )

type CmdM' env err m =
  ( MonadReader     env     m
  , MonadError          err m
  , MonadBaseControl IO     m
  --, MonadLogger             m
  -- , MonadRandom             m
  )

type CmdCommon env =
  ( HasConnectionPool env
  , HasConfig         env
  , HasMail           env
  , HasNLPServer      env )

type CmdM env err m =
  ( CmdM'     env err m
  , CmdCommon env
  )

type CmdRandom env err m =
  ( CmdM'             env err m
  , HasConnectionPool env
  , HasConfig         env
  , MonadRandom       m
  , HasMail           env
  )

type Cmd'' env err a = forall m.     CmdM''    env err m => m a
type Cmd'  env err a = forall m.     CmdM'     env err m => m a
type Cmd       err a = forall m env. CmdM      env err m => m a
type CmdR      err a = forall m env. CmdRandom env err m => m a



fromInt64ToInt :: Int64 -> Int
fromInt64ToInt = fromIntegral

-- TODO: ideally there should be very few calls to this functions.
mkCmd :: (Connection -> IO a) -> Cmd err a
mkCmd k = do
  pool <- view connPool
  withResource pool (liftBase . k)

runCmd :: (HasConnectionPool env)
       => env
       -> Cmd'' env err a
       -> IO (Either err a)
runCmd env m = runExceptT $ runReaderT m env

runOpaQuery :: Default FromFields fields haskells
            => Select fields
            -> Cmd err [haskells]
runOpaQuery q = mkCmd $ \c -> runSelect c q

runCountOpaQuery :: Select a -> Cmd err Int
runCountOpaQuery q = do
  counts <- mkCmd $ \c -> runSelect c $ countRows q
  -- countRows is guaranteed to return a list with exactly one row so DL.head is safe here
  pure $ fromInt64ToInt $ DL.head counts

formatPGSQuery :: PGS.ToRow a => PGS.Query -> a -> Cmd err DB.ByteString
formatPGSQuery q a = mkCmd $ \conn -> PGS.formatQuery conn q a

-- TODO use runPGSQueryDebug everywhere
runPGSQuery' :: (PGS.ToRow a, PGS.FromRow b) => PGS.Query -> a -> Cmd err [b]
runPGSQuery' q a = mkCmd $ \conn -> PGS.query conn q a

runPGSQuery :: ( CmdM env err m
               , PGS.FromRow r, PGS.ToRow q
               )
               => PGS.Query -> q -> m [r]
runPGSQuery q a = mkCmd $ \conn -> catch (PGS.query conn q a) (printError conn)
  where
    printError c (SomeException e) = do
      q' <- PGS.formatQuery c q a
      hPutStrLn stderr q'
      throw (SomeException e)

{-
-- TODO
runPGSQueryFold :: ( CmdM env err m
               , PGS.FromRow r
               )
               => PGS.Query -> a -> (a -> r -> IO a) -> m a
runPGSQueryFold q initialState consume = mkCmd $ \conn -> catch (PGS.fold_ conn initialState consume) (printError conn)
  where
    printError c (SomeException e) = do
      q' <- PGS.formatQuery c q
      hPutStrLn stderr q'
      throw (SomeException e)
-}



-- | TODO catch error
runPGSQuery_ :: ( CmdM env err m
               , PGS.FromRow r
               )
               => PGS.Query -> m [r]
runPGSQuery_ q = mkCmd $ \conn -> catch (PGS.query_ conn q) printError
  where
    printError (SomeException e) = do
      hPutStrLn stderr (fromQuery q)
      throw (SomeException e)

execPGSQuery :: PGS.ToRow a => PGS.Query -> a -> Cmd err Int64
execPGSQuery q a = mkCmd $ \conn -> PGS.execute conn q a

------------------------------------------------------------------------
databaseParameters :: FilePath -> IO PGS.ConnectInfo
databaseParameters fp = do
  ini <- readIniFile' fp
  let val' key = unpack $ val ini "database" key
  let dbPortRaw = val' "DB_PORT"
  let dbPort = case (readMaybe dbPortRaw :: Maybe Word16) of
        Nothing -> panic $ "DB_PORT incorrect: " <> (pack dbPortRaw)
        Just d  -> d

  pure $ PGS.ConnectInfo { PGS.connectHost     = val' "DB_HOST"
                         , PGS.connectPort     = dbPort
                         , PGS.connectUser     = val' "DB_USER"
                         , PGS.connectPassword = val' "DB_PASS"
                         , PGS.connectDatabase = val' "DB_NAME"
                         }

connectGargandb :: FilePath -> IO Connection
connectGargandb fp = databaseParameters fp >>= \params -> connect params

fromField' :: (Typeable b, FromJSON b) => Field -> Maybe DB.ByteString -> Conversion b
fromField' field mb = do
    v <- fromField field mb
    valueToHyperdata v
      where
          valueToHyperdata v = case fromJSON v of
             Success a  -> pure a
             Error _err -> returnError ConversionFailed field
                         $ DL.intercalate " " [ "cannot parse hyperdata for JSON: "
                                              , show v
                                              ]

printSqlOpa :: Default Unpackspec a a => Select a -> IO ()
printSqlOpa = putStrLn . maybe "Empty query" identity . showSql

dbCheck :: CmdM env err m => m Bool
dbCheck = do
  r :: [PGS.Only Text] <- runPGSQuery_ "select username from public.auth_user"
  case r of
    [] -> return False
    _  -> return True

restrictMaybe :: ( Default Opaleye.Internal.Operators.IfPP b b
                 , (Default Opaleye.Internal.Constant.ToFields Bool b))
              => MaybeFields a -> (a -> b) -> b
restrictMaybe v cond = matchMaybe v $ \case
  Nothing -> toFields True
  Just v' -> cond v'
