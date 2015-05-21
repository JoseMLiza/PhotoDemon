VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "pdUniscribeItem"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'Uniscribe Item Container
'Copyright 2015-2015 by Tanner Helland
'Created: 20/May/15
'Last updated: 20/May/15
'Last update: start migrating run-specific information into this class, to make it easier to handle complicated text layouts.
'
'This class is just a small container for holding individual Uniscribe item data.  We use a class instead of a struct because
' item coverage is highly variable; some items may hold a single glyph, while others hold 100+ glyphs.  It's impossible to
' predict run complexity until Uniscribe analyzes a string, then breaks it into individually shapeable items.
'
'We'll also need this functionality in the future to build a custom Rich-Textbox-type UC, so it makes sense to take full
' advantage of the functionality now.
'
'Relevant MSDN page for all things Uniscribe:
' https://msdn.microsoft.com/en-us/library/windows/desktop/dd374091%28v=vs.85%29.aspx
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Before proceeding further, it's worth explaining a few very confusing terms, which Uniscribe uses to describe the various
' units of text information it handles.  (Source: https://msdn.microsoft.com/en-us/library/windows/desktop/dd374094%28v=vs.85%29.aspx)

'ITEM:
' - ITEMS have a single script and direction (LTR or RTL).
' - ScriptItemize analyzes a *paragraph* and returns it as an array of ITEMS.  This means that Uniscribe *does not* handle text
'    larger than a paragraph, e.g. text that contains hard line breaks.  If a string contains hard line breaks (e.g. Cr/Lf chars),
'    you must subdivide it into paragraphs, then process each paragraph individually.
' - Simple text - e.g. text with a uniform style - may be both an ITEM and a RUN, but in general, you should not assume any equality
'    between these units.  This is true for even simple text, as Uniscribe prefers to break ITEMS on certain punctuation boundaries,
'    even if the script and direction do not change (and they thus would work fine as a RUN).
' - ITEMS can contain characters of multiple styles (font, size, color).  Note that this statement is very misleading, because
'    Uniscribe cannot automatically address or handle ITEMS consisting of multiple styles.  Rather, this means that ITEMS returned
'    by Uniscribe *can* be manually subdivided into smaller ITEMS of varying styles.  However, *YOU* must be the one to perform that
'    subdivision, as Uniscribe's itemizing function has no way for the caller to specify custom ITEM boundaries.
' - ITEM and RUN information are combined to create a full paragraph.

'RUN:
' - RUNS are contiguous passages of text with a uniform style (font, size, and color).
' - Multiple scripts (e.g. "languages" or "character sets", colloquially) are allowed in a RUN.
' - Unlike an ITEM, a RUN can contain both LTR and RTL content.

'These definitions are not hard and fast, and MSDN often uses one where it probably means the other.  I describe them here so
' you'll have compassion if I accidentally do the same.  ;)

'In general, I would prefer to use the term ITEM to describe a section of text with a uniform style, script, and direction.
' Multiple ITEMS can then be combined into a RUN, meaning a RUN always consists of one or more ITEMS.

'That definition makes much more sense to me, versus the gobbledygook used by Uniscribe's docs.

'-------------

'Now, onto the bits of per-item information this class stores.

'ScriptItemize is the first Uniscribe function called.  It divides a paragraph into individual items.  Each item has a uniform
' direction and script.  As an example, a sentence like "Hello [Arabic text] World" would consist of three items:
' "Hello"
' "[Arabic Text]"
' "World"

'"Hello" and "World" would be marked as LTR, while "[Arabic Text]" would be marked as RTL.  This is important, because we ultimately
' need to reorder RTL glyphs - post-shaping - into LTR order, to simplify the glyph rendering process.

'Anyway, this class represents a single item, meaning a single SCRIPT_ITEM struct as returned by ScriptItemize.
Private m_ScriptItem As SCRIPT_ITEM

'Upon generating our SCRIPT_ITEM copy, ScriptItemize also has knowledge of which chunk of the string our SCRIPT_ITEM represents.
' It will supply this substring via the get/setSubstring functions.  (Note that we also cache the length of this substring, as it's
' used for a lot of other calculations, like array bounds.
Private m_Substring As String
Private m_SubstringLength As Long

'For each item created by ScriptItemize, ScriptLayout generates a corresponding Visual/Logical mapping order.  We don't store
' that order here (pdUniscribe manages it internally), but I mention this as a reminder that the order of these class instances
' inside pdUnicode's master array may not match their on-screen order, and you need to be aware of that if mapping from visual
' position to logical position (e.g. for caret or cursor behavior).  You can't simply rely on the internal order provided by
' pdUnicode, as it may not match your intended purpose.

'For each item, ScriptShape generates a cache list and returns three pieces of data:

' 1) an index list for mapping between characters and glyphs.  (This has one entry for every character in the string.)
Private m_LogicalClusterCache() As Integer

' 2) a list of glyphs.  The size of this list is totally independent of characters, and must be addressed separately.
Private m_NumOfGlyphs As Long
Private m_GlyphCache() As Integer

' 3) an array of glyph attributes.  This has the same size as the glyph cache in (2).
Private m_VisualAttributesCache() As SCRIPT_VISATTR

'For each item, ScriptPlace generates three pieces of data:

' 1) An advance width cache (the distance between neighboring glyphs, basically)
Private m_AdvanceWidthCache() As Long

' 2) a glyph offset cache (the displacement of a glyph within a cell, typically used for diacritics with variable per-glyph positioning)
Private m_GlyphOffsetCache() As GOFFSET

' 3) a single ABC measurement for the ENTIRE item.  (This is helpful when positioning the starts and ends of lines, to avoid glyph overhang.)
Private m_ItemABCWidth As ABC

'ByRef + CopyMemory is confusing, especially when trading bare pointers (as I am prone to doing), so I prefer to use a ByVal-only
' version of RtlMoveMemory, and forcibly supply pointers to avoid the risk of messing things up.
Private Declare Sub CopyMemoryStrict Lib "kernel32" Alias "RtlMoveMemory" (ByVal lpDst As Long, ByVal lpSrc As Long, ByVal byteLength As Long)

Private Const DEFAULT_INITIAL_CACHE_SIZE As Long = 16

'Because VB doesn't allow a class to expose public UDTs (without a typelib, anyway), all custom structs use get/set functions.
' CopyMemory is used for a performance boost, but note that this doesn't work for variable-sized structs.
' (Those must be handled specially.)
Friend Sub getScriptItem(ByRef dstScriptItem As SCRIPT_ITEM)
    CopyMemoryStrict VarPtr(dstScriptItem), VarPtr(m_ScriptItem), Len(m_ScriptItem)
End Sub

Friend Sub setScriptItem(ByRef srcScriptItem As SCRIPT_ITEM)
    CopyMemoryStrict VarPtr(m_ScriptItem), VarPtr(srcScriptItem), Len(m_ScriptItem)
End Sub

'Passing bare pointers is cheaper than copying structs (or sub-structs), but please do not use these functions outside of pdUniscribe,
' and please do not cache their values.  This class may change memory allocations at any time, so you must always call these functions
' if you need a pointer to something.
Friend Function getScriptItemPointer() As Long
    getScriptItemPointer = VarPtr(m_ScriptItem)
End Function

Friend Function getScriptItemAnalysisPointer() As Long
    getScriptItemAnalysisPointer = VarPtr(m_ScriptItem.analysis)
End Function

'Substring is the only function that directly returns a value (since it uses an intrinsic VB type)
Public Function getSubstring() As String
    getSubstring = m_Substring
End Function

Public Sub setSubstring(ByVal newSubstring As String)
    m_Substring = newSubstring
    m_SubstringLength = Len(newSubstring)
End Sub

'ScriptShape generates three arrays for each item:
' 1) Logical cluster list (for mapping between characters and glyphs; same length as the substring)
' 2) Glyph list (actual indices into the font file for the generated glyphs; length is NOT the same as the substring)
' 3) Visual attributes list (extra display data for each glyph; same length as the glyph list)
'
'To improve performance, we copy all three of these simultaneously, at the end of ScriptShape processing.
Friend Sub setShapingData(ByRef logicalClusterCache() As Integer, ByVal numOfGlyphs As Long, ByRef glyphCache() As Integer, ByRef visualAttributesCache() As SCRIPT_VISATTR)
    
    'The logical cluster cache has the same length as our substring, so handle it separately
    If UBound(m_LogicalClusterCache) <> m_SubstringLength - 1 Then
        ReDim m_LogicalClusterCache(0 To m_SubstringLength - 1) As Integer
    End If
    
    CopyMemoryStrict VarPtr(m_LogicalClusterCache(0)), VarPtr(logicalClusterCache(0)), m_SubstringLength * 2
    
    'The glyph and visual attribute caches are the same size, so we can handle them together
    m_NumOfGlyphs = numOfGlyphs
    
    'Note that it is technically possible for a substring to not result in any actual glyphs.  (e.g. a bunch of zero-width control chars)
    ' This is still a valid return, and if it happens, we can't attempt to copy zero bytes of data.
    If m_NumOfGlyphs > 0 Then
    
        If UBound(m_GlyphCache) <> m_NumOfGlyphs - 1 Then
            ReDim m_GlyphCache(0 To m_NumOfGlyphs - 1) As Integer
            ReDim m_VisualAttributesCache(0 To m_NumOfGlyphs - 1) As SCRIPT_VISATTR
        End If
        
        CopyMemoryStrict VarPtr(m_GlyphCache(0)), VarPtr(glyphCache(0)), 2 * m_NumOfGlyphs
        CopyMemoryStrict VarPtr(m_VisualAttributesCache(0)), VarPtr(visualAttributesCache(0)), Len(m_VisualAttributesCache(0)) * m_NumOfGlyphs
        
    End If
    
End Sub

'While we can set all of ScriptShape's generated information at once, retrieving it is more helpful if we do it on a per-item basis.
Friend Function getNumOfGlyphs() As Long
    getNumOfGlyphs = m_NumOfGlyphs
End Function

'In some cases, it's easier (and much more lightweight!) to pass bare pointers to our various large structs and caches.
' Obviously, you MUST not cache these between requests, as this class may change its memory allocation at any time.
Friend Function getPointerToGlyphCache() As Long
    getPointerToGlyphCache = VarPtr(m_GlyphCache(0))
End Function

Friend Function getPointerToVisualAttributesCache() As Long
    getPointerToVisualAttributesCache = VarPtr(m_VisualAttributesCache(0))
End Function

'Similarly, sometimes we just want to grab a single entry at a given position.  For performance reasons, none of these wrappers check bounds.
' It's assumed that the caller is iterating using the result of getNumOfGlyphs(), so bounds won't be a problem.
Friend Function getGlyphCacheAtPosition(ByVal gPos As Long) As Long
    
    'Glyphs are returned by Uniscribe as 16-bit values.  Obviously, VB treats these values as if they are signed.
    ' To work around this, we forcibly deal with negative integer values.
    getGlyphCacheAtPosition = (m_GlyphCache(gPos) And &HFFFF&)
    
End Function

Friend Function getAdvanceWidthAtPosition(ByVal gPos As Long) As Long
    getAdvanceWidthAtPosition = m_AdvanceWidthCache(gPos)
End Function

Friend Sub copyGlyphOffsetToPointer(ByVal dstPointer As Long, ByVal gPos As Long)
    CopyMemoryStrict dstPointer, VarPtr(m_GlyphOffsetCache(gPos)), Len(m_GlyphOffsetCache(gPos))
End Sub

'ScriptPlace generates two arrays and one custom struct for each item:
' 1) Advance width list (distance between neighboring glyphs, basically)
' 2) Glyph offset list (displacement of a glyph within its cell; this is primarily used for diacritics with variable per-glyph positioning)
' 3) ABC measurement for the ENTIRE item.
'
'To improve performance, we copy all three of these simultaneously, at the end of ScriptPlace processing.
Friend Sub setPlacementData(ByRef advanceWidthCache() As Long, ByRef glyphOffsetCache() As GOFFSET, ByRef itemABCWidth As ABC)
    
    'The advance width and glyph offset caches are the same size, so we can handle them together
    If m_NumOfGlyphs > 0 Then
    
        If UBound(m_GlyphOffsetCache) <> m_NumOfGlyphs - 1 Then
            ReDim m_GlyphOffsetCache(0 To m_NumOfGlyphs - 1) As GOFFSET
            ReDim m_AdvanceWidthCache(0 To m_NumOfGlyphs - 1) As Long
        End If
        
        CopyMemoryStrict VarPtr(m_GlyphOffsetCache(0)), VarPtr(glyphOffsetCache(0)), 4 * m_NumOfGlyphs
        CopyMemoryStrict VarPtr(m_AdvanceWidthCache(0)), VarPtr(advanceWidthCache(0)), Len(m_AdvanceWidthCache(0)) * m_NumOfGlyphs
        
    End If
    
    m_ItemABCWidth = itemABCWidth
    
End Sub

Private Sub Class_Initialize()
    
    'Size all arrays to a nice minimum size, to reduce churn if the user is only working with small strings
    ReDim m_LogicalClusterCache(0 To DEFAULT_INITIAL_CACHE_SIZE - 1) As Integer
    ReDim m_GlyphCache(0 To DEFAULT_INITIAL_CACHE_SIZE - 1) As Integer
    ReDim m_VisualAttributesCache(0 To DEFAULT_INITIAL_CACHE_SIZE - 1) As SCRIPT_VISATTR
    ReDim m_AdvanceWidthCache(0 To DEFAULT_INITIAL_CACHE_SIZE - 1) As Long
    ReDim m_GlyphOffsetCache(0 To DEFAULT_INITIAL_CACHE_SIZE - 1) As GOFFSET
        
End Sub