{-|
Module      : Gargantext.Core
Description : Supported Natural language
Copyright   : (c) CNRS, 2017-Present
License     : AGPL + CECILL v3
Maintainer  : team@gargantext.org
Stability   : experimental
Portability : POSIX

-}

module Gargantext.Core
  where

------------------------------------------------------------------------
-- | Language of a Text
-- For simplicity, we suppose text has an homogenous language
-- 
-- Next steps: | DE | IT | SP
--
--  - EN == english
--  - FR == french
--  - DE == deutch  (not implemented yet)
--  - IT == italian (not implemented yet)
--  - SP == spanish (not implemented yet)
--
--  ... add your language and help us to implement it (:
data Lang = EN | FR
