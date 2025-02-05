{-|
Module      : Gargantext.Core.Text.Terms.Mono
Description : Mono Terms module
Copyright   : (c) CNRS, 2017 - present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

Mono-terms are Nterms where n == 1.

-}


module Gargantext.Core.Text.Terms.Mono (monoTerms, monoTexts, monoTextsBySentence, words)
  where

import Prelude (String)

import Data.Text (Text)
import qualified Data.Text as T

import qualified Data.List as L
import qualified Data.Set as S

import Gargantext.Core
import Gargantext.Core.Types
import Gargantext.Core.Text.Terms.Mono.Stem (stem)

import Gargantext.Prelude
--import Data.Char (isAlphaNum, isSpace)

-- | TODO remove Num ?
--isGram  c  = isAlphaNum c

words :: Text -> [Text]
words = monoTexts

-- | Sentence split separators
isSep :: Char -> Bool
isSep = (`elem` (",.:;?!(){}[]\"\'" :: String))

monoTerms :: Lang -> Text -> [TermsWithCount]
monoTerms l txt = map (\t -> (monoText2term l t, 1)) $ monoTexts txt

monoTexts :: Text -> [Text]
monoTexts = L.concat . monoTextsBySentence

-- | TODO use text2term only
monoText2term :: Lang -> Text -> Terms
monoText2term lang txt = Terms [txt] (S.singleton $ stem lang txt)

monoTextsBySentence :: Text -> [[Text]]
monoTextsBySentence = map T.words
                    . T.split isSep
                    . T.toLower
