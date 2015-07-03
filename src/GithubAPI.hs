
module GithubAPI
  ( getReadme
  , getUser
  ) where

import Import
import Text.Blaze.Html (preEscapedToHtml)
import qualified Control.Monad.Catch as Catch
import qualified Data.ByteString.Lazy as BL
import qualified Data.Aeson as A
import qualified Data.HashMap.Strict as HashMap
import Text.XML.HXT.Core
import Data.CaseInsensitive (CI)
import qualified Language.PureScript.Docs as D

-- | Get a repository readme, rendered as HTML.
getReadme ::
  (MonadCatch m, MonadIO m, HasHttpManager env, MonadReader env m) =>
  Maybe GithubAuthToken ->
  D.GithubUser ->
  D.GithubRepo ->
  String -> -- ^ ref: commit, branch, etc.
  m (Either HttpException Html)
getReadme mauth user repo ref =
  (liftM . liftM) go (getReadme' mauth user repo ref)
  where
  go = preEscapedToHtml . stripH1 . unpack . decodeUtf8

getReadme' ::
  (MonadCatch m, MonadIO m, HasHttpManager env, MonadReader env m) =>
  Maybe GithubAuthToken ->
  D.GithubUser ->
  D.GithubRepo ->
  String -> -- ^ ref: commit, branch, etc.
  m (Either HttpException BL.ByteString)
getReadme' mauth (D.GithubUser user) (D.GithubRepo repo) _ =
  let query = "" -- TODO: this will do for now; should really be ("ref=" ++ ref)
      headers = [("Accept", mediaTypeHtml)] ++ authHeader mauth
  in githubAPI ["repos", user, repo, "readme"] query headers

-- | Get the currently logged in user.
getUser ::
  (MonadCatch m, MonadIO m, HasHttpManager env, MonadReader env m) =>
  GithubAuthToken -> m (Either HttpException (Maybe D.GithubUser))
getUser token =
  (liftM . liftM) go (getUser' token)
  where
  go = liftM D.GithubUser . (loginFromJSON <=< A.decode)
  loginFromJSON val =
    case val of
      A.Object obj ->
        case HashMap.lookup "login" obj of
          Just (A.String t) -> Just $ unpack t
          _                 -> Nothing
      _            -> Nothing

getUser' ::
  (MonadCatch m, MonadIO m, HasHttpManager env, MonadReader env m) =>
  GithubAuthToken -> m (Either HttpException BL.ByteString)
getUser' auth =
  let headers = [("Accept", "application/json")] ++ authHeader (Just auth)
  in githubAPI ["user"] "" headers

githubAPI ::
  (MonadCatch m, MonadIO m, HasHttpManager env, MonadReader env m) =>
  [String] -> -- ^ Path parts
  String -> -- ^ Query string
  [(CI ByteString, ByteString)] -> -- ^ Extra headers
  m (Either HttpException BL.ByteString)
githubAPI path query extraHeaders = do
  tryHttp $ do
    initReq <- parseGithubUrlWithQuery path query
    let headers = [("User-Agent", "Pursuit")] ++ extraHeaders
    let req = initReq { requestHeaders = headers }
    liftM responseBody $ httpLbs req

authHeader :: Maybe GithubAuthToken -> [(CI ByteString, ByteString)]
authHeader mauth =
   maybe []
         (\t -> [("Authorization", "bearer " <> runGithubAuthToken t)])
         mauth

stripH1 :: String -> String
stripH1 = unsafeHead . runLA stripH1Arrow
  where
  stripH1Arrow =
    hread >>>
      processTopDown (neg (hasName "h1") `guards` this) >>>
      writeDocumentToString []

mediaTypeHtml :: ByteString
mediaTypeHtml = "application/vnd.github.v3.html"

parseGithubUrlWithQuery :: MonadThrow m => [String] -> String -> m Request
parseGithubUrlWithQuery parts query =
  parseUrl $ concat [ "https://api.github.com/"
                    , intercalate "/" parts
                    , "?"
                    , query
                    ]

tryHttp :: MonadCatch m => m a -> m (Either HttpException a)
tryHttp = Catch.try
