{-# LANGUAGE RecordWildCards, DeriveDataTypeable #-}
{-|

Options common to most hledger reports.

-}

module Hledger.Reports.ReportOptions (
  ReportOpts(..),
  BalanceType(..),
  FormatStr,
  defreportopts,
  rawOptsToReportOpts,
  dateSpanFromOpts,
  intervalFromOpts,
  clearedValueFromOpts,
  whichDateFromOpts,
  journalSelectingAmountFromOpts,
  queryFromOpts,
  queryFromOptsOnly,
  queryOptsFromOpts,
  reportSpans,
  transactionDateFn,
  postingDateFn,

  tests_Hledger_Reports_ReportOptions
)
where

import Data.Data (Data)
import Data.Typeable (Typeable)
import Data.Time.Calendar
import Safe (headMay, lastMay)
import System.Console.CmdArgs.Default  -- some additional default stuff
import Test.HUnit

import Hledger.Data
import Hledger.Query
import Hledger.Utils


type FormatStr = String

-- | Which balance is being shown in a multi-column balance report.
data BalanceType = PeriodBalance     -- ^ The change of balance in each period.
                 | CumulativeBalance -- ^ The accumulated balance at each period's end, starting from zero at the report start date.
                 | HistoricalBalance -- ^ The historical balance at each period's end, starting from the account balances at the report start date.
  deriving (Eq,Show,Data,Typeable)

instance Default BalanceType where def = PeriodBalance

-- | Standard options for customising report filtering and output,
-- corresponding to hledger's command-line options and query language
-- arguments. Used in hledger-lib and above.
data ReportOpts = ReportOpts {
     begin_          :: Maybe Day
    ,end_            :: Maybe Day
    ,period_         :: Maybe (Interval,DateSpan)
    ,cleared_        :: Bool
    ,uncleared_      :: Bool
    ,cost_           :: Bool
    ,depth_          :: Maybe Int
    ,display_        :: Maybe DisplayExp
    ,date2_          :: Bool
    ,empty_          :: Bool
    ,no_elide_       :: Bool
    ,real_           :: Bool
    ,daily_          :: Bool
    ,weekly_         :: Bool
    ,monthly_        :: Bool
    ,quarterly_      :: Bool
    ,yearly_         :: Bool
    ,format_         :: Maybe FormatStr
    ,query_          :: String -- all arguments, as a string
    -- register
    ,average_        :: Bool
    ,related_        :: Bool
    -- balance
    ,balancetype_    :: BalanceType
    ,flat_           :: Bool -- mutually
    ,tree_           :: Bool -- exclusive
    ,drop_           :: Int
    ,no_total_       :: Bool
 } deriving (Show, Data, Typeable)

instance Default ReportOpts where def = defreportopts

defreportopts :: ReportOpts
defreportopts = ReportOpts
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def
    def

rawOptsToReportOpts :: RawOpts -> IO ReportOpts
rawOptsToReportOpts rawopts = do
  d <- getCurrentDay
  return defreportopts{
     begin_       = maybesmartdateopt d "begin" rawopts
    ,end_         = maybesmartdateopt d "end" rawopts
    ,period_      = maybeperiodopt d rawopts
    ,cleared_     = boolopt "cleared" rawopts
    ,uncleared_   = boolopt "uncleared" rawopts
    ,cost_        = boolopt "cost" rawopts
    ,depth_       = maybeintopt "depth" rawopts
    ,display_     = maybedisplayopt d rawopts
    ,date2_       = boolopt "date2" rawopts
    ,empty_       = boolopt "empty" rawopts
    ,no_elide_    = boolopt "no-elide" rawopts
    ,real_        = boolopt "real" rawopts
    ,daily_       = boolopt "daily" rawopts
    ,weekly_      = boolopt "weekly" rawopts
    ,monthly_     = boolopt "monthly" rawopts
    ,quarterly_   = boolopt "quarterly" rawopts
    ,yearly_      = boolopt "yearly" rawopts
    ,format_      = maybestringopt "format" rawopts
    ,query_       = unwords $ listofstringopt "args" rawopts -- doesn't handle an arg like "" right
    ,average_     = boolopt "average" rawopts
    ,related_     = boolopt "related" rawopts
    ,balancetype_ = balancetypeopt rawopts
    ,flat_        = boolopt "flat" rawopts
    ,tree_        = boolopt "tree" rawopts
    ,drop_        = intopt "drop" rawopts
    ,no_total_    = boolopt "no-total" rawopts
    }

balancetypeopt :: RawOpts -> BalanceType
balancetypeopt rawopts
    | length [o | o <- ["cumulative","historical"], isset o] > 1
                         = optserror "please specify at most one of --cumulative and --historical"
    | isset "cumulative" = CumulativeBalance
    | isset "historical" = HistoricalBalance
    | otherwise          = PeriodBalance
    where
      isset = flip boolopt rawopts

maybesmartdateopt :: Day -> String -> RawOpts -> Maybe Day
maybesmartdateopt d name rawopts =
        case maybestringopt name rawopts of
          Nothing -> Nothing
          Just s -> either
                    (\e -> optserror $ "could not parse "++name++" date: "++show e)
                    Just
                    $ fixSmartDateStrEither' d s

type DisplayExp = String

maybedisplayopt :: Day -> RawOpts -> Maybe DisplayExp
maybedisplayopt d rawopts =
    maybe Nothing (Just . regexReplaceBy "\\[.+?\\]" fixbracketeddatestr) $ maybestringopt "display" rawopts
    where
      fixbracketeddatestr "" = ""
      fixbracketeddatestr s = "[" ++ fixSmartDateStr d (init $ tail s) ++ "]"

maybeperiodopt :: Day -> RawOpts -> Maybe (Interval,DateSpan)
maybeperiodopt d rawopts =
    case maybestringopt "period" rawopts of
      Nothing -> Nothing
      Just s -> either
                (\e -> optserror $ "could not parse period option: "++show e)
                Just
                $ parsePeriodExpr d s

-- | Figure out the date span we should report on, based on any
-- begin/end/period options provided. A period option will cause begin and
-- end options to be ignored.
dateSpanFromOpts :: Day -> ReportOpts -> DateSpan
dateSpanFromOpts _ ReportOpts{..} =
    case period_ of Just (_,span) -> span
                    Nothing -> DateSpan begin_ end_

-- | Figure out the reporting interval, if any, specified by the options.
-- --period overrides --daily overrides --weekly overrides --monthly etc.
intervalFromOpts :: ReportOpts -> Interval
intervalFromOpts ReportOpts{..} =
    case period_ of
      Just (interval,_) -> interval
      Nothing -> i
          where i | daily_ = Days 1
                  | weekly_ = Weeks 1
                  | monthly_ = Months 1
                  | quarterly_ = Quarters 1
                  | yearly_ = Years 1
                  | otherwise =  NoInterval

-- | Get a maybe boolean representing the last cleared/uncleared option if any.
clearedValueFromOpts :: ReportOpts -> Maybe Bool
clearedValueFromOpts ReportOpts{..} | cleared_   = Just True
                                    | uncleared_ = Just False
                                    | otherwise  = Nothing

-- depthFromOpts :: ReportOpts -> Int
-- depthFromOpts opts = min (fromMaybe 99999 $ depth_ opts) (queryDepth $ queryFromOpts nulldate opts)

-- | Report which date we will report on based on --date2.
whichDateFromOpts :: ReportOpts -> WhichDate
whichDateFromOpts ReportOpts{..} = if date2_ then SecondaryDate else PrimaryDate

-- | Select the Transaction date accessor based on --date2.
transactionDateFn :: ReportOpts -> (Transaction -> Day)
transactionDateFn ReportOpts{..} = if date2_ then transactionDate2 else tdate

-- | Select the Posting date accessor based on --date2.
postingDateFn :: ReportOpts -> (Posting -> Day)
postingDateFn ReportOpts{..} = if date2_ then postingDate2 else postingDate


-- | Convert this journal's postings' amounts to the cost basis amounts if
-- specified by options.
journalSelectingAmountFromOpts :: ReportOpts -> Journal -> Journal
journalSelectingAmountFromOpts opts
    | cost_ opts = journalConvertAmountsToCost
    | otherwise = id

-- | Convert report options and arguments to a query.
queryFromOpts :: Day -> ReportOpts -> Query
queryFromOpts d opts@ReportOpts{..} = simplifyQuery $ And $ [flagsq, argsq]
  where
    flagsq = And $
              [(if date2_ then Date2 else Date) $ dateSpanFromOpts d opts]
              ++ (if real_ then [Real True] else [])
              ++ (if empty_ then [Empty True] else []) -- ?
              ++ (maybe [] ((:[]) . Status) (clearedValueFromOpts opts))
              ++ (maybe [] ((:[]) . Depth) depth_)
    argsq = fst $ parseQuery d query_

-- | Convert report options to a query, ignoring any non-flag command line arguments.
queryFromOptsOnly :: Day -> ReportOpts -> Query
queryFromOptsOnly d opts@ReportOpts{..} = simplifyQuery flagsq
  where
    flagsq = And $
              [(if date2_ then Date2 else Date) $ dateSpanFromOpts d opts]
              ++ (if real_ then [Real True] else [])
              ++ (if empty_ then [Empty True] else []) -- ?
              ++ (maybe [] ((:[]) . Status) (clearedValueFromOpts opts))
              ++ (maybe [] ((:[]) . Depth) depth_)

tests_queryFromOpts :: [Test]
tests_queryFromOpts = [
 "queryFromOpts" ~: do
  assertEqual "" Any (queryFromOpts nulldate defreportopts)
  assertEqual "" (Acct "a") (queryFromOpts nulldate defreportopts{query_="a"})
  assertEqual "" (Desc "a a") (queryFromOpts nulldate defreportopts{query_="desc:'a a'"})
  assertEqual "" (Date $ mkdatespan "2012/01/01" "2013/01/01")
                 (queryFromOpts nulldate defreportopts{begin_=Just (parsedate "2012/01/01")
                                                      ,query_="date:'to 2013'"
                                                      })
  assertEqual "" (Date2 $ mkdatespan "2012/01/01" "2013/01/01")
                 (queryFromOpts nulldate defreportopts{query_="edate:'in 2012'"})
  assertEqual "" (Or [Acct "a a", Acct "'b"])
                 (queryFromOpts nulldate defreportopts{query_="'a a' 'b"})
 ]

-- | Convert report options and arguments to query options.
queryOptsFromOpts :: Day -> ReportOpts -> [QueryOpt]
queryOptsFromOpts d ReportOpts{..} = flagsqopts ++ argsqopts
  where
    flagsqopts = []
    argsqopts = snd $ parseQuery d query_

tests_queryOptsFromOpts :: [Test]
tests_queryOptsFromOpts = [
 "queryOptsFromOpts" ~: do
  assertEqual "" [] (queryOptsFromOpts nulldate defreportopts)
  assertEqual "" [] (queryOptsFromOpts nulldate defreportopts{query_="a"})
  assertEqual "" [] (queryOptsFromOpts nulldate defreportopts{begin_=Just (parsedate "2012/01/01")
                                                             ,query_="date:'to 2013'"
                                                             })
 ]

-- | Calculate the overall and (if a reporting interval is specified)
-- per-interval date spans for a report, based on command-line
-- options, the search query, and the journal data.
--
-- The basic overall report span is:
-- without -E: the intersection of the requested span and the matched data's span.
-- with -E:    the full requested span, including leading/trailing intervals that are empty.
--             If the begin or end date is not specified, those of the journal are used.
--
-- The report span will be enlarged if necessary to include a whole
-- number of report periods, when a reporting interval is specified.
--
reportSpans ::  ReportOpts -> Query -> Journal -> [Posting] -> (DateSpan, [DateSpan])
reportSpans opts q j matchedps = (reportspan, spans)
  where
    (reportspan, spans)
      | empty_ opts = (dbg "reportspan1" $ enlargedrequestedspan, sps)
      | otherwise   = (dbg "reportspan2" $ requestedspan `spanIntersect` matchedspan, sps)
      where
        sps = dbg "spans" $ splitSpan (intervalFromOpts opts) reportspan

    -- the requested span specified by the query (-b/-e/-p options and query args);
    -- might be open-ended
    requestedspan = dbg "requestedspan" $ queryDateSpan (date2_ opts) q

    -- the requested span with unspecified dates filled from the journal data
    finiterequestedspan = dbg "finiterequestedspan" $ requestedspan `orDatesFrom` journalDateSpan j

    -- enlarge the requested span to a whole number of periods
    enlargedrequestedspan = dbg "enlargedrequestedspan" $
                            DateSpan (maybe Nothing spanStart $ headMay requestedspans)
                                     (maybe Nothing spanEnd   $ lastMay requestedspans)
      where
        -- spans of the requested report interval which enclose the requested span
        requestedspans = dbg "requestedspans" $ splitSpan (intervalFromOpts opts) finiterequestedspan

    -- earliest and latest dates of matched postings
    matchedspan = dbg "matchedspan" $ postingsDateSpan' (whichDateFromOpts opts) matchedps


tests_Hledger_Reports_ReportOptions :: Test
tests_Hledger_Reports_ReportOptions = TestList $
    tests_queryFromOpts
 ++ tests_queryOptsFromOpts
