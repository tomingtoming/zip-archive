-- Test suite for Codec.Archive.Zip
-- runghc Test.hs

import Codec.Archive.Zip
import System.Directory
import Test.HUnit.Base
import Test.HUnit.Text
import System.Time
import System.Process
import qualified Data.ByteString.Lazy as B
import Control.Applicative

-- define equality for Archives so timestamps aren't distinguished if they
-- correspond to the same MSDOS datetime.
instance Eq Archive where
  (==) a1 a2 =  zSignature a1 == zSignature a2
             && zComment a1 == zComment a2
             && (all id $ zipWith (\x y -> x { eLastModified = eLastModified x `div` 2  } ==
                                           y { eLastModified = eLastModified y `div` 2  }) (zEntries a1) (zEntries a2))

main :: IO Counts
main = do
  createDirectory "test-temp"
  counts <- runTestTT $ TestList [ 
                                   testReadWriteArchive
                                 , testReadExternalZip
                                 , testFromToArchive
                                 , testReadWriteEntry
                                 , testAddFilesOptions
                                 , testDeleteEntries
                                 , testExtractFiles
                                 ]
  removeDirectoryRecursive "test-temp"
  return counts

testReadWriteArchive = TestCase $ do
  archive <- addFilesToArchive [OptRecursive] emptyArchive ["LICENSE", "Codec"]
  B.writeFile "test-temp/test1.zip" $ fromArchive archive
  archive' <- toArchive <$> B.readFile "test-temp/test1.zip"
  assertEqual "for writing and reading test1.zip" archive archive'
  assertEqual "for writing and reading test1.zip" archive archive'

testReadExternalZip = TestCase $ do
  runCommand "/usr/bin/zip -q -9 test-temp/test4.zip zip-archive.cabal Codec/Archive/Zip.hs" >>= waitForProcess
  archive <- toArchive <$> B.readFile "test-temp/test4.zip"
  let files = filesInArchive archive
  assertEqual "for results of filesInArchive" ["zip-archive.cabal", "Codec/Archive/Zip.hs"] files
  cabalContents <- B.readFile "zip-archive.cabal"
  case findEntryByPath "zip-archive.cabal" archive of 
       Nothing  -> assertFailure "zip-archive.cabal not found in archive"
       Just f   -> assertEqual "for contents of zip-archive.cabal in archive" cabalContents (fromEntry f)

testFromToArchive = TestCase $ do
  archive <- addFilesToArchive [OptRecursive] emptyArchive ["LICENSE", "Codec"]
  assertEqual "for (toArchive $ fromArchive archive)" archive (toArchive $ fromArchive archive)

testReadWriteEntry = TestCase $ do
  entry <- readEntry [] "zip-archive.cabal"
  setCurrentDirectory "test-temp"
  writeEntry [] entry
  setCurrentDirectory ".."
  entry' <- readEntry [] "test-temp/zip-archive.cabal"
  let entry'' = entry' { eRelativePath    = eRelativePath entry
                       , eRawRelativePath = eRawRelativePath entry
                       , eLastModified    = eLastModified entry }
  assertEqual "for readEntry -> writeEntry -> readEntry" entry entry''

testAddFilesOptions = TestCase $ do
  archive1 <- addFilesToArchive [OptVerbose] emptyArchive ["LICENSE", "Codec"]
  archive2 <- addFilesToArchive [OptRecursive, OptVerbose] archive1 ["LICENSE", "Codec"]
  assertBool "for recursive and nonrecursive addFilesToArchive"
     (length (filesInArchive archive1) < length (filesInArchive archive2))

testDeleteEntries = TestCase $ do
  archive1 <- addFilesToArchive [] emptyArchive ["LICENSE", "Codec/"] 
  let archive2 = deleteEntryFromArchive "LICENSE" archive1
  let archive3 = deleteEntryFromArchive "Codec/" archive2
  assertEqual "for deleteFilesFromArchive" emptyArchive archive3

testExtractFiles = TestCase $ do
  createDirectory "test-temp/dir1"
  createDirectory "test-temp/dir1/dir2"
  let hiMsg = "hello there"
  let helloMsg = "Hello there. This file is very long.  Longer than 31 characters."
  writeFile "test-temp/dir1/hi" hiMsg
  writeFile "test-temp/dir1/dir2/hello" helloMsg
  archive <- addFilesToArchive [OptRecursive] emptyArchive ["test-temp/dir1"]
  removeDirectoryRecursive "test-temp/dir1"
  extractFilesFromArchive [OptVerbose] archive
  hi <- readFile "test-temp/dir1/hi"
  hello <- readFile "test-temp/dir1/dir2/hello"
  assertEqual "contents of test-temp/dir1/hi" hiMsg hi
  assertEqual "contents of test-temp/dir1/dir2/hello" helloMsg hello

