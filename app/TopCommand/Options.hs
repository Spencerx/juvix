module TopCommand.Options where

import Commands.Clean.Options
import Commands.Compile.Options
import Commands.Dependencies.Options qualified as Dependencies
import Commands.Dev.Options qualified as Dev
import Commands.Doctor.Options
import Commands.Eval.Options
import Commands.Format.Options
import Commands.Html.Options
import Commands.Init.Options
import Commands.Isabelle.Options
import Commands.Markdown.Options
import Commands.Repl.Options
import Commands.Typecheck.Options
import Commands.Version.Options
import CommonOptions hiding (Doc)
import Data.Generics.Uniplate.Data
import GlobalOptions

data TopCommand
  = DisplayVersion
  | DisplayNumericVersion
  | JuvixVersion VersionCommand
  | DisplayHelp
  | Typecheck TypecheckOptions
  | Compile CompileCommand
  | Clean CleanOptions
  | Eval EvalOptions
  | Html HtmlOptions
  | Markdown MarkdownOptions
  | Isabelle IsabelleOptions
  | Dev Dev.DevCommand
  | Doctor DoctorOptions
  | Init InitOptions
  | JuvixRepl ReplOptions
  | JuvixFormat FormatOptions
  | Dependencies Dependencies.DependenciesCommand
  deriving stock (Data)

topCommandInputPath :: TopCommand -> IO (Maybe (SomePath Abs))
topCommandInputPath t = do
  d <- firstJustM getInputFileOrDir (universeBi t)
  f <- firstJustM getInputFile (universeBi t)
  return (f <|> d)
  where
    getInputFile :: AppPath File -> IO (Maybe (SomePath Abs))
    getInputFile p
      | p ^. pathIsInput = do
          cwd <- getCurrentDir
          Just . File <$> prepathToAbsFile cwd (p ^. pathPath)
      | otherwise = return Nothing

    getInputFileOrDir :: AppPath FileOrDir -> IO (Maybe (SomePath Abs))
    getInputFileOrDir p
      | p ^. pathIsInput = getInputPathFromPrepathFileOrDir (p ^. pathPath)
      | otherwise = return Nothing

getInputPathFromPrepathFileOrDir :: Prepath FileOrDir -> IO (Maybe (SomePath Abs))
getInputPathFromPrepathFileOrDir p = do
  cwd <- getCurrentDir
  lr <- fromPreFileOrDir cwd p
  return . Just $ case lr of
    Left file -> File file
    Right dir -> Dir dir

parseDisplayVersion :: Parser TopCommand
parseDisplayVersion =
  flag'
    DisplayVersion
    ( long "version"
        <> short 'v'
        <> help "Show version information"
    )

parseDisplayNumericVersion :: Parser TopCommand
parseDisplayNumericVersion =
  flag'
    DisplayNumericVersion
    ( long "numeric-version"
        <> help "Show only the version number"
    )

parseDisplayHelp :: Parser TopCommand
parseDisplayHelp =
  flag'
    DisplayHelp
    ( long "help"
        <> short 'h'
        <> help "Show the help text"
    )

parseUtility :: Parser TopCommand
parseUtility =
  hsubparser
    ( mconcat
        [ commandGroup "Utility commands:",
          metavar "UTILITY_CMD",
          commandInit,
          commandRepl,
          commandFormat,
          commandVersion,
          commandClean,
          commandDependencies,
          commandDoctor,
          commandDev
        ]
    )
  where
    commandInit :: Mod CommandFields TopCommand
    commandInit =
      command
        "init"
        ( info
            (Init <$> parseInitOptions)
            (progDesc "Interactively initialize a Juvix project in the current directory")
        )
    commandDoctor :: Mod CommandFields TopCommand
    commandDoctor =
      command
        "doctor"
        ( info
            (Doctor <$> parseDoctorOptions)
            (progDesc "Perform checks on your Juvix development environment")
        )
    commandRepl :: Mod CommandFields TopCommand
    commandRepl =
      command
        "repl"
        ( info
            (JuvixRepl <$> parseRepl)
            (progDesc "Run the Juvix REPL")
        )

    commandVersion :: Mod CommandFields TopCommand
    commandVersion =
      command "version" $
        info
          (JuvixVersion <$> parseVersionCommand)
          ( progDesc "Print the Juvix version in different formats"
          )

    commandFormat :: Mod CommandFields TopCommand
    commandFormat =
      command "format" $
        info
          (JuvixFormat <$> parseFormat)
          ( headerDoc
              ( Just
                  ( vsep
                      [ "juvix format is used to format Juvix source files.",
                        "",
                        "Given a file, it prints the reformatted source to standard output.",
                        "Given a project directory it prints a list of unformatted files in the project.",
                        "Given no argument it prints a list of unformatted files in the project which contains the current directory."
                      ]
                  )
              )
              <> progDesc "Format a Juvix file or Juvix project"
          )

    commandClean :: Mod CommandFields TopCommand
    commandClean =
      command
        "clean"
        (info (Clean <$> parseCleanOptions) (progDesc "Delete build artifacts"))

    commandDependencies :: Mod CommandFields TopCommand
    commandDependencies =
      command
        "dependencies"
        (info (Dependencies <$> Dependencies.parseDependenciesCommand) (progDesc "Subcommands related to dependencies"))

commandCheck :: Mod CommandFields TopCommand
commandCheck =
  command "typecheck" $
    info
      (Typecheck <$> parseTypecheck)
      (progDesc "Typecheck a Juvix file")

commandCompile :: Mod CommandFields TopCommand
commandCompile =
  command "compile" $
    info
      (Compile <$> parseCompileCommand)
      (progDesc "Compile a Juvix file")

commandEval :: Mod CommandFields TopCommand
commandEval =
  command "eval" $
    info
      (Eval <$> parseEvalOptions)
      (progDesc "Evaluate a Juvix file")

commandHtml :: Mod CommandFields TopCommand
commandHtml =
  command "html" $
    info
      (Html <$> parseHtml)
      (progDesc "Generate HTML for a Juvix file")

commandMarkdown :: Mod CommandFields TopCommand
commandMarkdown =
  command "markdown" $
    info
      (Markdown <$> parseJuvixMarkdown)
      (progDesc "Translate Juvix code blocks in a Markdown file to Markdown")

commandIsabelle :: Mod CommandFields TopCommand
commandIsabelle =
  command "isabelle" $
    info
      (Isabelle <$> parseIsabelle)
      (progDesc "Translate a Juvix file to Isabelle/HOL")

commandDev :: Mod CommandFields TopCommand
commandDev =
  command "dev" $
    info
      (Dev <$> Dev.parseDevCommand)
      (progDesc "Commands for the Juvix compiler developers")

parseCompilerCommand :: Parser TopCommand
parseCompilerCommand =
  hsubparser
    ( mconcat
        [ commandGroup "Compiler commands:",
          metavar "COMPILER_CMD",
          commandCheck,
          commandCompile,
          commandEval,
          commandHtml,
          commandMarkdown,
          commandIsabelle
        ]
    )

parseTopCommand :: Parser TopCommand
parseTopCommand =
  parseDisplayVersion
    <|> parseDisplayNumericVersion
    <|> parseDisplayHelp
    <|> parseCompilerCommand
    <|> parseUtility

descr :: ParserInfo (GlobalOptions, TopCommand)
descr =
  info
    ( do
        cli <- parseTopCommand
        opts <- parseGlobalFlags
        return (opts, cli)
    )
    ( fullDesc
        <> progDesc "The Juvix compiler."
        <> footerDoc (Just foot)
    )
  where
    foot :: AnsiDoc
    foot = annotate bold "maintainers: " <> "The Juvix Team"
