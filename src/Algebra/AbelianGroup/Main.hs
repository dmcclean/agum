-- Unification and matching in Abelian groups
-- John D. Ramsdell -- August 2009

module Main (main, test) where

import Data.Char (isSpace, isAlpha, isAlphaNum, isDigit)
import Data.List (sort)
import System.IO (isEOF)

-- Chapter 8, Section 5 of the Handbook of Automated Reasoning by
-- Franz Baader and Wayne Snyder describes unification and matching in
-- communtative/monoidal theories.  This module refines the described
-- algorithms for the special case of Abelian groups.

-- In this module, an Abelian group is a free algebra over a signature
-- with three function symbols,
--
-- * the binary symbol +, the group operator,
-- * a constant 0, the identity element, and
-- * the unary symbol -, the inverse operator.
--
-- The algebra is generated by a set of variables.  Syntactically, a
-- variable is an identifer such as x and y.

-- The axioms associated with the algebra are:
--
-- * x + y = y + x                 Commutativity
-- * (x + y) + z = x + (y + z)     Associativity
-- * x + 0 = x                     Group identity
-- * x + -x = 0                    Cancellation

-- A substitution maps variables to terms.  A substitution s is
-- extended to a term as follows.
--
--     s(0) = 0
--     s(-t) = -s(t)
--     s(t + t') = s(t) + s(t')

-- The unification problem is given the problem statement t =? t',
-- find a substitution s such that s(t) = s(t') modulo the axioms of
-- the algebra.  The matching problem is to find substitution s such
-- that s(t) = t' modulo the axioms.

-- A term is represented as the sum of factors, and a factor is the
-- product of an integer coeficient and a variable or the group
-- identity, zero.  In this representation, every coeficient is
-- non-zero, and no variable occurs twice.

-- A term can be represented by a finite map from variables to
-- non-negative integers.  To make the code easier to understand,
-- association lists are used instead of Data.Map.

newtype Lin = Lin [(String, Int)]

-- Constructors

-- Identity element (zero)
ide :: Lin
ide = Lin []

-- Variables
var :: String -> Lin
var x = Lin [(x, 1)]

-- Multiply coefficients
mul :: Int -> Lin -> Lin
mul 0 (Lin _) = ide
mul 1 t = t
mul n (Lin t) = 
    Lin $ map (\(x, c) -> (x, n * c)) t

-- Invert by negating coefficients.
neg :: Lin -> Lin
neg (Lin t) =
    Lin $ map (\(x, c) -> (x, negate c)) t

-- Join terms ensuring that coefficients are non-zero, and no variable
-- occurs twice.
add :: Lin -> Lin -> Lin
add (Lin t) (Lin t') =
    Lin $ foldr f t' t
    where
      f (x, c) t =
          case lookup x t of
            Just c' | c + c' == 0 -> remove x t
                    | otherwise -> (x, c + c') : remove x t
            Nothing -> (x, c) : t

-- Remove the first pair in an association list that matches the key.
remove :: Eq a => a -> [(a, b)] -> [(a, b)]
remove _ [] = []
remove x (y@(z, _) : ys)
       | x == z = ys
       | otherwise = y : remove x ys

canonicalize :: Lin -> Lin
canonicalize (Lin t) =
    Lin (sort t)

-- Convert a linearized term into an association list.
assocs :: Lin -> [(String, Int)]
assocs (Lin t) = t

term :: [(String, Int)] -> Lin
term assoc =
    foldr f ide assoc
    where
      f (x, c) t = add t $ mul c $ var x

-- Unification and Matching

newtype Equation = Equation (Lin, Lin)

newtype Maplet = Maplet (String, Lin)

-- Unification is the same as matching when there are no constants
unify :: Monad m => Equation -> m [Maplet]
unify (Equation (t0, t1)) =
    match $ Equation (add t0 (neg t1), ide)

-- Matching in Abelian groups is performed by finding integer
-- solutions to linear equations, and then using the solutions to
-- construct a most general unifier.
match :: Monad m => Equation -> m [Maplet]
match (Equation (t0, t1)) =
    case (assocs t0, assocs t1) of
      ([], []) -> return []
      ([], _) -> fail "no solution"
      (t0, t1) ->
          do
            subst <- intLinEq (map snd t0) (map snd t1)
            return $ mgu (map fst t0) (map fst t1) subst

-- Construct a most general unifier from a solution to a linear
-- equation.  The function adds the variables back into terms, and
-- generates fresh variables as needed.
mgu :: [String] -> [String] -> Subst -> [Maplet]
mgu vars syms subst =
    foldr f [] (zip vars [0..])
    where
      f (x, n) maplets =
          case lookup n subst of
            Just (factors, consts) ->
                Maplet (x, g factors consts) : maplets
            Nothing ->
                Maplet (x, var $ genSym n) : maplets
      g factors consts =
          term (zip genSyms factors ++ zip syms consts)
      genSyms = map genSym [0..]

-- Generated variables start with this character.
genChar :: Char
genChar = 'g'

genSym :: Int -> String
genSym i = genChar : show i

-- So why solve linear equations?  Consider the matching problem
--
--     c[0]*x[0] + c[1]*x[1] + ... + c[n-1]*x[n-1] =?
--         d[0]*a[0] + d[1]*a[1] + ... + d[m-1]*a[m-1]
--
-- with n variables and m constants.  We seek a most general unifier s
-- such that
--
--     s(c[0]*x[0] + c[1]*x[1] + ... + c[n-1]*x[n-1]) =
--         d[0]*a[0] + d[1]*a[1] + ... + d[m-1]*a[m-1]
--
-- which is the same as
--
--     c[0]*s(x[0]) + c[1]*s(x[1]) + ... + c[n-1]*s(x[n-1]) =
--         d[0]*a[0] + d[1]*a[1] + ... + d[m-1]*a[m-1]
--
-- Notice that the number of occurrences of constant a[0] in s(x[0])
-- plus s(x[1]) ... s(x[n-1]) must equal d[0].  Thus the mappings of
-- the unifier that involve constant a[0] respect integer solutions of
-- the following linear equation.
--
--     c[0]*x[0] + c[1]*x[1] + ... + c[n-1]*x[n-1] = d[0]
--
-- To compute a most general unifier, a most general integer solution
-- to a linear equation must be found.

-- Integer Solutions of Linear Inhomogeneous Equations

type LinEq = ([Int], [Int])

-- A linear equation with integer coefficients is represented as a
-- pair of lists of integers, the coefficients and the constants.  If
-- there are no constants, the linear equation represented by (c, [])
-- is the homogeneous equation:
--
--     c[0]*x[0] + c[1]*x[1] + ... + c[n-1]*x[n-1] = 0
--
-- where n is the length of c.  Otherwise, (c, d) represents a
-- sequence of inhomogeneous linear equations with the same
-- left-hand-side:
--
--     c[0]*x[0] + c[1]*x[1] + ... + c[n-1]*x[n-1] = d[0]
--     c[0]*x[0] + c[1]*x[1] + ... + c[n-1]*x[n-1] = d[1]
--     ...
--     c[0]*x[0] + c[1]*x[1] + ... + c[n-1]*x[n-1] = d[m-1]
--
-- where m is the length of d.

type Subst = [(Int, LinEq)]

-- A solution is a partial map from variables to terms, and a term is
-- a pair of lists of integers, the variable part of the term followed
-- by the constant part.  The variable part may specify variables not
-- in the input.  For example, the solution of
--
--     64x = 41y + 1
--
-- is x = -41z - 16 and y = -64z - 25.  The computed solution is read
-- off the list returned as an answer.
--
-- intLinEq [64,-41] [1] =
--     [(0,([0,0,0,0,0,0,-41],[-16])),
--      (1,([0,0,0,0,0,0,-64],[-25]))]

-- Find integer solutions to linear equations
intLinEq :: Monad m => [Int] -> [Int] -> m Subst
intLinEq coefficients constants =
    intLinEqLoop (length coefficients) (coefficients, constants) []

-- The algorithm used to find solutions is described in Vol. 2 of The
-- Art of Computer Programming / Seminumerical Alorithms, 2nd Ed.,
-- 1981, by Donald E. Knuth, pg. 327.

-- On input, n is the number of variables in the original problem, c
-- is the coefficients, d is the constants, and subst is a list of
-- eliminated variables.
intLinEqLoop :: Monad m => Int -> LinEq -> Subst -> m Subst
intLinEqLoop n (c, d) subst =
    -- Find the smallest non-zero coefficient in absolute value
    let (i, ci) = smallest c in
    case () of
      _ | ci < 0 -> intLinEqLoop n (invert c, invert d) subst
      --  Ensure the smallest coefficient is positive
        | ci == 0 -> fail "bad problem"
      --  Lack of non-zero coefficients is an error
        | ci == 1 ->
      --  A general solution of the following form has been found:
      --    x[i] = sum[j] -c'[j]*x[j] + d[k] for all k
      --  where c' is c with c'[i] = 0.
            return $ eliminate n (i, (invert (zero i c), d)) subst
        | divisible ci c ->
      --  If all the coefficients are divisible by c[i], a solution is
      --  immediate if all the constants are divisible by c[i],
      --  otherwise there is no solution.
            if divisible ci d then
                let c' = divide ci c
                    d' = divide ci d in
                return $ eliminate n (i, (invert (zero i c'), d')) subst
            else
                fail "no solution"
        | otherwise ->
      --  Eliminate x[i] in favor of freshly created variable x[n],
      --  where n is the length of c.
      --    x[n] = sum[j] (c[j] div c[i] * x[j])
      --  The new equation to be solved is:
      --    c[i]*x[n] + sum[j] (c[j] mod c[i])*x[j] = d[k] for all k
            intLinEqLoop n (map (\x -> mod x ci) c ++ [ci], d) subst'
            where
              subst' = eliminate n (i, (invert c' ++ [1], [])) subst
              c' = divide ci (zero i c)

-- Find the smallest non-zero coefficient in absolute value
smallest :: [Int] -> (Int, Int)
smallest xs =
    foldl f (-1, 0) (zip [0..] xs)
    where
      f (i, n) (j, x)
        | n == 0 = (j, x)
        | x == 0 || abs n <= abs x = (i, n)
        | otherwise = (j, x)

invert :: [Int] -> [Int]
invert t = map negate t

-- Zero the ith position in a list
zero :: Int -> [Int] -> [Int]
zero _ [] = []
zero 0 (_:xs) = 0 : xs
zero i (x:xs) = x : zero (i - 1) xs

-- Eliminate a variable from the existing substitution.  If the
-- variable is in the original problem, add it to the substitution.
eliminate :: Int -> (Int, LinEq) -> Subst -> Subst
eliminate n m@(i, (c, d)) subst =
    if i < n then
        m : map f subst
    else
        map f subst
    where
      f m'@(i', (c', d')) =     -- Eliminate i in c' if it occurs in c'
          case get i c' of
            0 -> m'             -- i is not in c'
            ci -> (i', (addmul ci (zero i c') c, addmul ci d' d))
      -- Find ith coefficient
      get _ [] = 0
      get 0 (x:_) = x
      get i (_:xs) = get (i - 1) xs
      -- addnum n xs ys sums xs and ys after multiplying ys by n
      addmul 1 [] ys = ys
      addmul n [] ys = map (* n) ys
      addmul _ xs [] = xs
      addmul n (x:xs) (y:ys) = (x + n * y) : addmul n xs ys

divisible :: Int -> [Int] -> Bool
divisible small t =
    all (\x -> mod x small == 0) t

divide :: Int -> [Int] -> [Int]
divide small t =
    map (\x -> div x small) t

-- Input and Output

instance Show Lin where
    showsPrec _ (Lin []) =
        showString "0"
    showsPrec _ x =
        showFactor t . showl ts
        where
          Lin (t:ts) = canonicalize x
          showFactor (x, 1) = showString x
          showFactor (x, -1) = showChar '-' . showString x
          showFactor (x, c) = shows c . showString x
          showl [] = id
          showl ((s,n):ts)
              | n < 0 =
                  showString " - " . showFactor (s, negate n) . showl ts
          showl (t:ts) = showString " + " . showFactor t . showl ts

instance Read Lin where
    readsPrec _ s0 =
        [ (t1, s2)       | (t0, s1) <- readSummand s0,
                           (t1, s2) <- readRest t0 s1 ]
        where
          readPrimary s0 =
              [ (t0, s1) | (x, s1) <- scan s0, isVar x,
                           let t0 = var x ] ++
              [ (t0, s1) | ("0", s1) <- scan s0,
                           let t0 = ide ] ++
              [ (t0, s3) | ("(", s1) <- scan s0,
                           (t0, s2) <- reads s1,
                           (")", s3) <- scan s2 ]
          readFactor s0 =
              [ (t0, s1) | (t0, s1) <- readPrimary s0 ] ++
              [ (t1, s2) | (n, s1) <- scan s0, isNum n, n /= "0",
                           (t0, s2) <- readPrimary s1,
                           let t1 = mul (read n) t0 ]
          readSummand s0 =
              [ (t0, s1) | (t0, s1) <- readFactor s0 ] ++
              [ (t1, s2) | ("-", s1) <- scan s0,
                           (t0, s2) <- readFactor s1,
                           let t1 = neg t0 ]
          readRest t0 s0 =
              [ (t2, s3) | ("+", s1) <- scan s0,
                           (t1, s2) <- readSummand s1,
                           (t2, s3) <- readRest (add t0 t1) s2 ] ++
              [ (t2, s3) | ("-", s1) <- scan s0,
                           (t1, s2) <- readFactor s1,
                           (t2, s3) <- readRest (add t0 (neg t1)) s2 ] ++
              [ (t0, s0) | (s, _) <- scan s0, s /= "+" && s /= "-" ]

isNum :: String -> Bool
isNum (c:_) = isDigit c
isNum _ = False

isVar :: String -> Bool
isVar (c:_) = isAlpha c && c /= genChar
isVar _ = False

scan :: ReadS String
scan "" = [("", "")]
scan (c:s)
    | isSpace c = scan s
    | isAlpha c = [ (c:part, t) | (part,t) <- [span isAlphaNum s] ]
    | isDigit c = [ (c:part, t) | (part,t) <- [span isDigit s] ]
    | otherwise = [([c], s)]

instance Show Equation where
    showsPrec _ (Equation (t0, t1)) =
        shows t0 . showString " = " . shows t1

instance Read Equation where
    readsPrec _ s0 =
        [ (Equation (t0, t1), s3) | (t0, s1) <- reads s0,
                                    ("=", s2) <- scan s1,
                                    (t1, s3) <- reads s2 ]

instance Show Maplet where
    showsPrec _ (Maplet (x, t)) =
        showString x . showString " -> " . shows t

-- Test Routine

-- Given an equation, display a unifier and a matcher.
test :: String -> IO ()
test prob =
    case readM prob of
      Err err -> putStrLn err
      Ans (Equation (t0, t1)) ->
          do
            putStr "Problem:   "
            print $ Equation (canonicalize t0, canonicalize t1)
            subst <- unify $ Equation (t0, t1)
            putStr "Unifier:   "
            print subst
            putStr "Matcher:   "
            case match $ Equation (t0, t1) of
              Err err -> putStrLn err
              Ans subst -> print subst
            putStrLn ""

readM :: (Read a, Monad m) => String -> m a
readM s =
    case [ x | (x, t) <- reads s, ("", "") <- lex t ] of
      [x] -> return x
      [] -> fail "no parse"
      _ -> fail "ambiguous parse"

data AnsErr a
    = Ans a
    | Err String

instance Monad AnsErr where
    (Ans x) >>= k = k x
    (Err s) >>= _ = Err s
    return        = Ans
    fail          = Err

main :: IO ()
main =
    do
      done <- isEOF
      case done of
        True -> return ()
        False ->
            do
              prob <- getLine
              test prob
              main
