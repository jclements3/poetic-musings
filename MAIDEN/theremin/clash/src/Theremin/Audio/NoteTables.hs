{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TemplateHaskell #-}
{-|
The default 'NoteMap' tables, evaluated once by Template Haskell so the
netlist gets constants and never sees a 'Double'. (Stage restriction: the
builders have to live in another module, hence the split from
"Theremin.Audio.NoteMap".) 'defaultNoteTable' is for simulation only —
synthesis reads the same numbers from the @$readmemb@ files.
-}
module Theremin.Audio.NoteTables
  ( defaultNoteTable
  , defaultPhaseTable
  , defaultAmpTable
  ) where

import Clash.Prelude

import Theremin.Audio.NoteMap

defaultNoteTable :: NoteTable
defaultNoteTable = $(listToVecTH (noteTableList defaultNoteMapParams))

defaultPhaseTable :: PhaseTable
defaultPhaseTable = $(listToVecTH (phaseTableList defaultNoteMapParams))

defaultAmpTable :: AmpTable
defaultAmpTable = $(listToVecTH (ampTableList defaultAmpMapParams))
