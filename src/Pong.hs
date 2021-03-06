{-# language
        BangPatterns
      , DuplicateRecordFields
      , OverloadedStrings
      , LambdaCase
      , NamedFieldPuns
      , ScopedTypeVariables
  #-}

module Pong (main) where

import Control.Concurrent (forkIO)
import Control.Monad (replicateM_)
import Data.Primitive (PrimArray)
import Data.Word (Word64)
import Net.Types (IPv4,IPv4Range)
import Options.Applicative ((<**>))
import System.IO (stderr)

import qualified Data.Map.Unboxed.Unboxed as MUU
import qualified Data.Map.Unboxed.Unlifted as MUN
import qualified Data.Primitive as PM
import qualified Data.Set.Unboxed as SU
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Text.Lazy.Builder as TB
import qualified Data.Text.Lazy.Builder.Int as TBI
import qualified Data.Text.Lazy.IO as TLIO
import qualified Net.IPv4 as IPv4
import qualified Network.Icmp.Ping as Ping
import qualified Options.Applicative as P

main :: IO ()
main = do
  cmd <- P.execParser $ P.info
    (commandParser <**> P.helper)
    P.fullDesc
  run cmd

printError :: Ping.IcmpException -> IO ()
printError err
  | err == Ping.IcmpExceptionSocket 13 = TIO.hPutStrLn stderr "Unable to create a raw socket."
  | otherwise = TIO.hPutStrLn stderr (T.pack (show err))

run :: Command -> IO ()
run = \case
  CommandHost Host{address,timeout} -> Ping.host (timeout * 1000000) address >>= \case
    Left err -> printError err
    Right m -> case m of
      Nothing -> TIO.hPutStrLn stderr "Timed out"
      Just ns -> TLIO.putStrLn (TB.toLazyText (TBI.decimal ns))
  CommandHosts Hosts{address,timeout} ->
    Ping.hosts (timeout * 1000000) (SU.fromList address) >>= \case
      Left err -> printError err
      Right m -> printHosts m
  CommandRange Range{range,timeout} ->
    Ping.range (timeout * 1000000) range >>= \case
      Left err -> printError err
      Right m -> printHosts m
  CommandMultihosts Multihosts{address,timeout,requests,cutoff,delay} ->
    Ping.multihosts (timeout * 1000000) (delay * 1000000) requests cutoff (SU.fromList address) >>= \case
      Left err -> printError err
      Right m -> printMultihosts m
  CommandMultirange Multirange{range,timeout,requests,cutoff,delay} ->
    Ping.multirange (timeout * 1000000) (delay * 1000000) requests cutoff range >>= \case
      Left err -> printError err
      Right m -> printMultihosts m
  CommandBlast b -> do
    blast b
    putStrLn "Press enter to exit."
    _ <- getLine
    pure ()
  CommandBlastRange b -> do
    blastRange b
    putStrLn "Press enter to exit."
    _ <- getLine
    pure ()
  CommandBlastRanges b -> do
    blastRanges b
    putStrLn "Press enter to exit."
    _ <- getLine
    pure ()

printHosts :: MUU.Map IPv4 Word64 -> IO ()
printHosts = MUU.traverseWithKey_
  ( \addr ns -> TLIO.putStrLn $ TB.toLazyText $
      IPv4.builder addr <> ": " <> TBI.decimal ns
  )

printMultihosts :: MUN.Map IPv4 (PrimArray Word64) -> IO ()
printMultihosts = MUN.foldlMapWithKeyM'
  ( \addr resps -> do
    TLIO.putStr (TB.toLazyText (IPv4.builder addr <> TB.singleton ':'))
    PM.traversePrimArray_
      ( \ns -> TLIO.putStr (TB.toLazyText (TB.singleton ' '<> TBI.decimal ns))
      ) resps
    TIO.putStr (T.singleton '\n')
  )

data Command
  = CommandHost Host
  | CommandHosts Hosts
  | CommandRange Range
  | CommandMultihosts Multihosts
  | CommandMultirange Multirange
  | CommandBlast Blast
  | CommandBlastRange BlastRange
  | CommandBlastRanges BlastRanges

blast :: Blast -> IO ()
blast Blast{address,threads} = replicateM_ threads $ forkIO $
  let go = do { _ <- Ping.host 1 address; go; }
  in go

blastRange :: BlastRange -> IO ()
blastRange BlastRange{range,threads} = replicateM_ threads $ forkIO $
  let go = do { _ <- Ping.range 1 range; go; }
  in go

blastRanges :: BlastRanges -> IO ()
blastRanges BlastRanges{ranges,threads} = mapM_ forkIO
  (fmap (\rng -> blastRange (BlastRange rng threads)) ranges)

data Blast = Blast
  { address :: !IPv4
  , threads :: !Int -- ^ how many threads to spin up
  }

data BlastRange = BlastRange
  { range :: !IPv4Range
  , threads :: !Int -- ^ how many threads to spin up
  }

data BlastRanges = BlastRanges
  { ranges :: [IPv4Range]
  , threads :: !Int -- ^ how many threads to spin up
  }

data Host = Host
  { timeout :: !Int -- seconds
  , address :: !IPv4
  }

data Hosts = Hosts
  { timeout :: !Int -- seconds
  , address :: [IPv4]
  }

data Range = Range
  { timeout :: !Int -- seconds
  , range :: !IPv4Range
  }

data Multihosts = Multihosts
  { timeout :: !Int -- seconds
  , delay :: !Int -- seconds
  , requests :: !Int
  , cutoff :: !Int
  , address :: [IPv4]
  }

data Multirange = Multirange
  { timeout :: !Int -- seconds
  , delay :: !Int -- seconds
  , requests :: !Int
  , cutoff :: !Int
  , range :: !IPv4Range
  }

commandParser :: P.Parser Command
commandParser = P.hsubparser $ mconcat
  [ P.command "host" $ P.info
      (CommandHost <$> hostParser)
      (P.progDesc "One ICMP echo request to a single host")
  , P.command "hosts" $ P.info
      (CommandHosts <$> hostsParser)
      (P.progDesc "One ICMP echo request to each argument host")
  , P.command "range" $ P.info
      (CommandRange <$> rangeParser)
      (P.progDesc "One ICMP echo request to each host in range")
  , P.command "multihosts" $ P.info
      (CommandMultihosts <$> multihostsParser)
      (P.progDesc "Multiple ICMP echo requests to each argument host")
  , P.command "multirange" $ P.info
      (CommandMultirange <$> multirangeParser)
      (P.progDesc "Multiple ICMP echo requests to each host in range")
  , P.command "blast" $ P.info
      (CommandBlast <$> blastParser)
      (P.progDesc "Stress-test a host")
  , P.command "blast-range" $ P.info
      (CommandBlastRange <$> blastRangeParser)
      (P.progDesc "Stress-test a range of hosts")
  , P.command "blast-ranges" $ P.info
      (CommandBlastRanges <$> blastRangesParser)
      (P.progDesc "Stress-test several ranges of hosts")
  ]

blastParser :: P.Parser Blast
blastParser = Blast
  <$> P.argument ipReadM
      ( P.metavar "HOST"
      <> P.help "IPv4 address of destination"
      )
  <*> P.option P.auto
      ( P.long "threads"
      <> P.short 't'
      <> P.metavar "THREADS"
      <> P.value 100
      <> P.showDefault
      <> P.help "Number of threads to spin up to blast."
      )

hostParser :: P.Parser Host
hostParser = Host
  <$> P.option P.auto
      ( P.long "timeout"
     <> P.short 't'
     <> P.metavar "SECONDS"
     <> P.value 3
     <> P.help "Timeout in seconds"
      )
  <*> P.argument ipReadM
      ( P.metavar "HOST"
     <> P.help "IPv4 address of destination"
      )

hostsParser :: P.Parser Hosts
hostsParser = Hosts
  <$> P.option P.auto
      ( P.long "timeout"
     <> P.short 't'
     <> P.metavar "SECONDS"
     <> P.value 3
     <> P.help "Timeout in seconds"
      )
  <*> P.some
      ( P.argument ipReadM
      ( P.metavar "HOST"
     <> P.help "IPv4 address of destination"
      )
      )

rangeParser :: P.Parser Range
rangeParser = Range
  <$> P.option P.auto
      ( P.long "timeout"
     <> P.short 't'
     <> P.metavar "SECONDS"
     <> P.value 3
     <> P.help "Timeout in seconds"
      )
  <*> P.argument ipRangeReadM
      ( P.metavar "RANGE"
     <> P.help "Destinations as IPv4 range in CIDR notation"
      )

blastRangeParser :: P.Parser BlastRange
blastRangeParser = BlastRange
  <$> P.argument ipRangeReadM
      ( P.metavar "RANGE"
      <> P.help "Destination as IPv4 range in CIDR notation"
      )
  <*> P.option P.auto
      ( P.long "threads"
      <> P.short 't'
      <> P.metavar "THREADS"
      <> P.value 100
      <> P.showDefault
      <> P.help "Number of threads to spin up to blast."
      )

blastRangesParser :: P.Parser BlastRanges
blastRangesParser = BlastRanges
  <$> P.some
      ( P.argument ipRangeReadM
        ( P.metavar "RANGE"
        <> P.help "Destination as IPv4 range in CIDR notation"
        )
      )
  <*> P.option P.auto
      ( P.long "threads"
      <> P.short 't'
      <> P.metavar "THREADS"
      <> P.value 100
      <> P.showDefault
      <> P.help "Number of threads to spin up to blast."
      )

multihostsParser :: P.Parser Multihosts
multihostsParser = Multihosts
  <$> P.option P.auto
      ( P.long "timeout"
     <> P.short 't'
     <> P.metavar "SECONDS"
     <> P.value 3
     <> P.help "Timeout in seconds"
      )
  <*> P.option P.auto
      ( P.long "delay"
     <> P.short 'd'
     <> P.metavar "SECONDS"
     <> P.value 0
     <> P.help "Delay in seconds bewteen ICMP requests to same host"
      )
  <*> P.option P.auto
      ( P.long "requests"
     <> P.short 'r'
     <> P.metavar "INT"
     <> P.value 3
     <> P.help "Number of pings per host"
      )
  <*> P.option P.auto
      ( P.long "cutoff"
     <> P.short 'c'
     <> P.metavar "INT"
     <> P.value 2
     <> P.help "Nonresponsive cutoff"
      )
  <*> P.some
      ( P.argument ipReadM
      ( P.metavar "HOST"
     <> P.help "IPv4 address of destination"
      )
      )

multirangeParser :: P.Parser Multirange
multirangeParser = Multirange
  <$> P.option P.auto
      ( P.long "timeout"
     <> P.short 't'
     <> P.metavar "SECONDS"
     <> P.value 3
     <> P.help "Timeout in seconds"
      )
  <*> P.option P.auto
      ( P.long "delay"
     <> P.short 'd'
     <> P.metavar "SECONDS"
     <> P.value 0
     <> P.help "Delay in seconds bewteen ICMP requests to same host"
      )
  <*> P.option P.auto
      ( P.long "requests"
     <> P.short 'r'
     <> P.metavar "INT"
     <> P.value 3
     <> P.help "Number of pings per host"
      )
  <*> P.option P.auto
      ( P.long "cutoff"
     <> P.short 'c'
     <> P.metavar "INT"
     <> P.value 2
     <> P.help "Nonresponsive cutoff"
      )
  <*> P.argument ipRangeReadM
      ( P.metavar "RANGE"
     <> P.help "Destinations as IPv4 range in CIDR notation"
      )

ipReadM :: P.ReadM IPv4
ipReadM = P.maybeReader (IPv4.decode . T.pack)

ipRangeReadM :: P.ReadM IPv4Range
ipRangeReadM = P.maybeReader (IPv4.decodeRange . T.pack)
