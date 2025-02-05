{-|
Module      : CleanCsvCorpus.hs
Description : Gargantext starter
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

Given a Gargantext CSV File and its Query This script cleans and
compress the contexts around the main terms of the query.
-}


module CleanCsvCorpus  where

--import GHC.IO (FilePath)
import Data.Either (Either(..))
import Data.SearchEngine as S
import qualified Data.Set as S
import Data.Text (pack)
import Data.Vector (Vector)
import qualified Data.Vector as V

import Gargantext.Prelude
import Gargantext.Core.Text.Search
import qualified Gargantext.Core.Text.Corpus.Parsers.CSV as CSV
------------------------------------------------------------------------

type Query = [S.Term]

filterDocs :: [DocId] -> Vector CSV.CsvGargV3 -> Vector CSV.CsvGargV3
filterDocs docIds = V.filter (\doc -> S.member (CSV.d_docId doc) $ S.fromList docIds )


main :: IO ()
main = do
  let rPath = "/tmp/Gargantext_Corpus.csv"
  let wPath = "/tmp/Gargantext_Corpus_bis.csv"
  --let q = ["water", "scarcity", "morocco", "shortage","flood"]
  let q = ["gratuit", "gratuité", "culture", "culturel"]

  eDocs <- CSV.readCSVFile rPath
  case eDocs of
    Right (h, csvDocs) -> do
      putStrLn $ "Number of documents before:" <> show (V.length csvDocs)
      putStrLn $ "Mean size of docs:" <> show ( CSV.docsSize csvDocs)

      let docs   = CSV.toDocs csvDocs
      let engine = insertDocs docs initialDocSearchEngine
      let docIds = S.query engine (map pack q)
      let docs'  = CSV.fromDocs $ filterDocs docIds (V.fromList docs)

      putStrLn $ "Number of documents after:" <> show (V.length docs')
      putStrLn $ "Mean size of docs:" <> show (CSV.docsSize docs')

      CSV.writeFile wPath (h, docs')
    Left e -> panic $ "Error: " <> (pack e)
