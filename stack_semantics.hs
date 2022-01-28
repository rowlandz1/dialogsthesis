import qualified Data.Set as Set
import Control.Monad.State

data Dialog = Empty
            | Atom String
            | I [String]
            | C [Dialog]
            | Up Dialog
--            | SPE [String]
--            | SPEstar [String]
            | SPE' [Dialog]
--            | PFA1 [String]
--            | PFA1star [String]
--            | PFAn [String]
--            | PFAnstar [String]
--            | PE [String]
--            | PEstar [String]
            | W [Dialog]
--            | Union Dialog Dialog

instance Show Dialog where
  show Empty     = "~"
  show (Atom s)  = s
  show (I ss)    = "(I " ++ unwords ss ++ ")"
  show (C ds)    = "(C " ++ unwords (show <$> ds) ++ ")"
  show (Up d)    = "(Up " ++ show d ++ ")"
  show (SPE' ds) = "(SPE' " ++ unwords (show <$> ds) ++ ")"
  show (W ds)    = "(W " ++ unwords (show <$> ds) ++ ")"

data Response = One String
              | Tup [String]

instance Show Response where
  show (One s) = s
  show (Tup ss) = "(" ++ unwords ss ++ ")"

-------------------------------------
----------- Simplification ----------
-------------------------------------

-- Completely simplify
simplify :: Dialog -> Dialog
simplify d = maybe d simplify (simplify1 d)

-- Convenience function. Same as simplify, but returns a Maybe so that
-- it can be used in monadic sequence.
simplifyM :: Dialog -> Maybe Dialog
simplifyM = Just . simplify

-- Applies a single simplification rule
simplify1 :: Dialog -> Maybe Dialog
-- Rule 1: zero subdialogs
simplify1 (C []) = Just Empty
simplify1 (W []) = Just Empty
simplify1 (I []) = Just Empty
--simplify1 (SPE []) = Just Empty
--simplify1 (SPEstar []) = Just Empty
simplify1 (SPE' []) = Just Empty
--simplify1 (PFA1 []) = Just Empty
--simplify1 (PFA1star []) = Just Empty
--simplify1 (PFAn []) = Just Empty
--simplify1 (PFAnstar []) = Just Empty
--simplify1 (PE []) = Just Empty
--simplify1 (PEstar []) = Just Empty
-- Rule 2: one subdialog
simplify1 (C [d]) = Just d
simplify1 (W [d]) = Just d
simplify1 (I [x]) = Just (Atom x)
--simplify1 (SPE [x]) = Just (Atom x)
--simplify1 (SPEstar [x]) = Just (Atom x)
simplify1 (SPE' [d]) = Just d
--simplify1 (PFA1 [x]) = Just (Atom x)
--simplify1 (PFA1star [x]) = Just (Atom x)
--simplify1 (PFAn [x]) = Just (Atom x)
--simplify1 (PFAnstar [x]) = Just (Atom x)
--simplify1 (PE [x]) = Just (Atom x)
--simplify1 (PEstar [x]) = Just (Atom x)
-- Other rules
simplify1 (C ds) = case removeEmptyDialogs ds of
  Just newsubs -> Just (C newsubs)
  Nothing      -> case flattenCurries ds of
    Just newsubs -> Just (C newsubs)
    Nothing      -> C <$> simplifyL ds
simplify1 (SPE' ds) = case removeEmptyDialogs ds of
  Just newsubs -> Just (SPE' newsubs)
  Nothing      -> SPE' <$> simplifyL ds
simplify1 (W ds) = case removeEmptyDialogs ds of
  Just newsubs -> Just (W newsubs)
  Nothing      -> W <$> simplifyL ds
--simplify1 (Union d1 d2) = case simplify1 d1 of
--  Just d1' -> Just (Union d1' d2)
--  Nothing  -> case simplify1 d2 of
--    Just d2' -> Just (Union d1 d2')
--    Nothing  -> Nothing
simplify1 _ = Nothing

-- Simplifies the first dialog it can
simplifyL :: [Dialog] -> Maybe [Dialog]
simplifyL [] = Nothing
simplifyL (d:ds) = case simplify1 d of
  Just newd -> Just (newd:ds)
  Nothing   -> (d:) <$> simplifyL ds

-----------------------------------------
-- Reduction
-----------------------------------------

data RS = RS [Dialog -> Dialog] Dialog [Response]

instance Show RS where
  show (RS lam d inp) = "(Lam{len=" ++ show (length lam) ++ "}, " ++ show d ++ ", " ++ show inp ++ ")"

-- Builts a reduction state and reduces as far as possible.
-- Should always reduce to at most one state.
dialogAcceptsInput :: Dialog -> [Response] -> Bool
dialogAcceptsInput d inp = case reduceStar [RS [const Empty] d inp] of
  [RS [] Empty []] -> True
  _                -> False

-- Reduce as far as possible
reduceStar :: [RS] -> [RS]
reduceStar rs = case rs >>= reduce of
  []  -> rs
  rs' -> reduceStar rs'

-- Implements the reduction relation (~>) described in the document.
-- The non-determinism is handled with lists.
reduce :: RS -> [RS]
-- [empty]
reduce (RS (f:lam) Empty inp) = [RS lam (f Empty) inp]
-- [atom]
reduce (RS (f:lam) (Atom x) ((One y):inp))
  | x == y    = [RS lam (f Empty) inp]
  | otherwise = []
-- [arrow]
reduce (RS (f1:f2:lam) (Up d) inp) = [RS (f2 . f1 : lam) d inp]
-- [C]
reduce (RS lam (C (d:ds)) inp) = [RS ((\d' -> simplify (C (d':ds))):lam) d inp]
-- [W]
reduce (RS lam (W ds) inp) =
  do (dcon, d) <- extractEach [] ds
     return (RS (dcon:lam) d inp)
  where extractEach d1 [] = []
        extractEach d1 (d:ds) = (\d' -> simplify (W (d1++[d']++ds)), d)
                              : extractEach (d1++[d]) ds
-- [SPE']
reduce (RS lam (SPE' ds) inp) =
  do (dcon, d) <- extractEach [] ds
     return (RS (dcon:lam) d inp)
  where extractEach d1 [] = []
        extractEach d1 (d:ds) = (\d' -> simplify (SPE' (d1++[d']++ds)), d)
                              : extractEach (d1++[d]) ds
-- [I]
reduce (RS (f:lam) (I ss) ((Tup rs):inp))
  | ss `setEq` rs = [RS lam (f Empty) inp]
  | otherwise     = []
reduce _ = []

--------------------------------
--- Staging
--------------------------------

type DialogState = StateT [Dialog -> Dialog] Maybe Dialog

stage :: Response -> Dialog -> DialogState
stage inp d =
  do dcons <- get
     case reduceStar [RS dcons d [inp]] of
       [RS dcons' d' []] ->
         do put dcons'
            return d'
       _ -> lift Nothing

--------------------------------
------ Utility Functions -------
--------------------------------

-- Removes empty dialogs from the list. Returns Nothing if nothing was removed.
removeEmptyDialogs :: [Dialog] -> Maybe [Dialog]
removeEmptyDialogs [] = Nothing
removeEmptyDialogs (Empty:ds) = Just (maybe ds id (removeEmptyDialogs ds))
removeEmptyDialogs (d:ds) = (d:) <$> removeEmptyDialogs ds

-- Removes C-dialogs from the list inserting the subdialogs instead. Only
-- a single layer is flattened.
flattenCurries :: [Dialog] -> Maybe [Dialog]
flattenCurries [] = Nothing
flattenCurries ((C cs):ds) = Just (cs ++ maybe ds id (flattenCurries ds))
flattenCurries (d:ds) = (d:) <$> flattenCurries ds

-- Convenience function. Wrapper around Set.isSubsetOf
subsetOf :: (Ord a) => [a] -> [a] -> Bool
subsetOf l1 l2 = Set.isSubsetOf (Set.fromList l1) (Set.fromList l2)

-- Convenience function. Wrapper around set equality
setEq :: (Ord a) => [a] -> [a] -> Bool
setEq l1 l2 = Set.fromList l1 == Set.fromList l2

-- Returns the first list with elements from the second list removed.
-- The order of the remaining elements is preserved.
setSubtract :: (Eq a) => [a] -> [a] -> [a]
setSubtract l1 [] = l1
setSubtract [] _ = []
setSubtract l1 (x:xs) = setSubtract (remove x l1) xs
  where remove _ [] = []
        remove y (x:xs) = if x == y then remove y xs else x : remove y xs

-- If the second list can be reordered into a prefix of the first list,
-- then the first list is returned with that prefix removed.
removePrefix :: (Ord a) => [a] -> [a] -> Maybe [a]
removePrefix list prefix = rmp list (Set.fromList prefix)
  where rmp [] prefix = if prefix == Set.empty then Just [] else Nothing
        rmp (x:xs) prefix
         | prefix == Set.empty = Just (x:xs)
         | Set.member x prefix = rmp xs (Set.delete x prefix)
         | otherwise           = Nothing

------------------------------------------------------
-- Tests. The result_ values should all be (Just ~) --
------------------------------------------------------
      
dialogA = W [C [Up (Atom "a"), Atom "b"], C [Atom "x", Atom "y"]]
rsA = RS [const Empty] dialogA [One "a", One "x", One "y", One "b"]

dialogB = W [I ["a", "b", "c"], I ["x", "y"]]
rsB = RS [const Empty] dialogB [Tup ["x", "y"], Tup ["a", "b", "c"]]
