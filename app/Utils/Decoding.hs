{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE BangPatterns #-}

module Utils.Decoding where

import Data.Maybe
import Data.ByteString.Lazy

import Control.DeepSeq
import Control.Monad

import System.Random (randomIO)
import Test.QuickCheck.Random (mkQCGen)
import Test.QuickCheck.Gen

import Test.QuickFuzz.Gen.FormatInfo

import Args
import Debug
import Exception
import Utils.Generation

import System.Directory hiding (listDirectory, withCurrentDirectory)
import Control.Exception ( bracket )

listDirectory :: FilePath -> IO [FilePath]
listDirectory path =
  (Prelude.filter f) <$> (getDirectoryContents path)
  where f filename = filename /= "." && filename /= ".."

withCurrentDirectory :: FilePath  -- ^ Directory to execute in
                     -> IO a      -- ^ Action to be executed
                     -> IO a
withCurrentDirectory dir action =
  bracket getCurrentDirectory setCurrentDirectory $ \ _ -> do
    setCurrentDirectory dir
    action

decodeFile decf file = do
    !buf <- Data.ByteString.Lazy.readFile file
    forceEvaluation (decf buf)

-- Decode the files inside a directory
strictDecodeDir :: (Show base, NFData base) => QFCommand -> FormatInfo base actions 
               -> IO [base]
strictDecodeDir cmd fmt = do
    fs <- listDirectory (inDir cmd)
    xs <- mapM makeRelativeToCurrentDirectory fs
    bsnfs <- withCurrentDirectory (inDir cmd) (mapM (decodeFile (decode fmt)) xs)

    --xs <- withCurrentDirectory (inDir cmd) (mapM (Data.ByteString.Lazy.readFile) xs)
    --bsnfs <- mapM (\x -> forceEvaluation ((decode fmt) x)) xs
    bsnfs <- return $ Prelude.filter isJust bsnfs
    bsnfs <- return $ Prelude.map fromJust bsnfs
    Prelude.putStrLn $ "Loaded " ++ (show (Prelude.length bsnfs)) ++ " of " ++ (show (Prelude.length fs)) ++ " files to mutate."
    return bsnfs


-- Decode a single file
strictDecodeFile :: (Show base, NFData base) => QFCommand -> FormatInfo base actions 
               -> IO [base]
strictDecodeFile cmd fmt = do
    let filename = inDir cmd 
    xs <- return [filename]
    bsnfs <- mapM (decodeFile (decode fmt)) xs
    bsnfs <- return $ Prelude.filter isJust bsnfs
    bsnfs <- return $ Prelude.map fromJust bsnfs
    --Prelude.putStrLn $ "Loaded " ++ (show (Prelude.length bsnfs)) ++ " of " ++ (show (Prelude.length fs)) ++ " files to mutate."
    return bsnfs


quickGen cmd fmt = let baseGen = resize (maxSize cmd) (random fmt)
                       baseVal = unGen baseGen (mkQCGen 0) 0
                   in return [baseVal]

strictDecode :: (Show base, NFData base) => QFCommand -> FormatInfo base actions 
               -> IO [base]
strictDecode cmd fmt = do
                       b <- System.Directory.doesFileExist (inDir cmd)
                       ys <- (if b then strictDecodeFile cmd fmt 
                                   else strictDecodeDir  cmd fmt)
                       if Prelude.null ys then (quickGen cmd fmt) --(error $ "Impossible to load " ++ (inDir cmd))
                                          else return ys
 

