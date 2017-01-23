VERSION 5.00
Begin VB.UserControl pdColorDepth 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   ClientHeight    =   5175
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   7170
   ControlContainer=   -1  'True
   DrawStyle       =   5  'Transparent
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   9.75
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   HasDC           =   0   'False
   ScaleHeight     =   345
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   478
   ToolboxBitmap   =   "pdColorDepth.ctx":0000
   Begin PhotoDemon.pdDropDown cboDepthGrayscale 
      Height          =   735
      Left            =   0
      TabIndex        =   6
      Top             =   840
      Width           =   7095
      _ExtentX        =   12515
      _ExtentY        =   1296
      Caption         =   "depth"
   End
   Begin PhotoDemon.pdDropDown cboDepthColor 
      Height          =   735
      Left            =   0
      TabIndex        =   5
      Top             =   840
      Width           =   7095
      _ExtentX        =   12515
      _ExtentY        =   1085
      Caption         =   "depth"
   End
   Begin PhotoDemon.pdDropDown cboAlphaModel 
      Height          =   735
      Left            =   0
      TabIndex        =   4
      Top             =   2880
      Width           =   7095
      _ExtentX        =   12515
      _ExtentY        =   1296
      Caption         =   "transparency"
   End
   Begin PhotoDemon.pdDropDown cboColorModel 
      Height          =   735
      Left            =   0
      TabIndex        =   3
      Top             =   0
      Width           =   7095
      _ExtentX        =   12515
      _ExtentY        =   1508
      Caption         =   "color model"
   End
   Begin PhotoDemon.pdSlider sldAlphaCutoff 
      Height          =   855
      Left            =   0
      TabIndex        =   0
      Top             =   4080
      Width           =   7095
      _ExtentX        =   12515
      _ExtentY        =   1508
      Caption         =   "alpha cut-off"
      Max             =   254
      SliderTrackStyle=   1
      Value           =   64
      GradientColorRight=   1703935
      NotchPosition   =   2
      NotchValueCustom=   64
   End
   Begin PhotoDemon.pdLabel lblColorCount 
      Height          =   375
      Left            =   4920
      Top             =   2460
      Width           =   2055
      _ExtentX        =   3625
      _ExtentY        =   661
      Caption         =   "palette size"
   End
   Begin PhotoDemon.pdSlider sldColorCount 
      Height          =   375
      Left            =   240
      TabIndex        =   1
      Top             =   2400
      Width           =   4575
      _ExtentX        =   8070
      _ExtentY        =   661
      Min             =   2
      Max             =   256
      Value           =   256
      NotchPosition   =   2
      NotchValueCustom=   256
   End
   Begin PhotoDemon.pdColorSelector clsAlphaColor 
      Height          =   975
      Left            =   0
      TabIndex        =   2
      Top             =   4080
      Width           =   7095
      _ExtentX        =   15690
      _ExtentY        =   1720
      Caption         =   "transparent color (right-click image to select)"
      curColor        =   16711935
   End
End
Attribute VB_Name = "pdColorDepth"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'Color/Transparency depth selector User Control
'Copyright 2016-2017 by Tanner Helland
'Created: 22/April/16
'Last updated: 19/January/17
'Last update: migrate copy+paste implementation to dedicated UC
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Public Event Change()

'For the "set alpha by color" option, the user should be allowed to click colors straight from the preview area.
' However, if "set alpha by color" is *not* set, color selection should be left to the parent dialog.
Public Event ColorSelectionRequired(ByVal selectState As Boolean)

'Because this control dynamically shows/hides subcontrols, its total height can vary.  Parent controls can
' use this to reflow other controls, as necessary
Public Event SizeChanged()

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'After reflowing controls, we store the final calculated "ideal" size of the control.  Our parent can ask us to
' sync to this size (although some may not care, and will ignore this).
Private m_IdealControlHeight As Long

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    UserControl.Enabled = newValue
    PropertyChanged "Enabled"
End Property

'If any text value is NOT valid, this will return FALSE
Public Function IsValid(Optional ByVal showErrors As Boolean = True) As Boolean
    
    IsValid = True
    
    'If a given text value is not valid, highlight the problem and optionally display an error message box
    If (Not sldAlphaCutoff.IsValid(showErrors)) Then
        IsValid = False
        Exit Function
    End If
    
    If (Not sldColorCount.IsValid(showErrors)) Then
        IsValid = False
        Exit Function
    End If
    
End Function

'For the "set alpha by color" option, external callers can notify us of color changes via this sub.
Public Sub NotifyNewAlphaColor(ByVal newColor As Long)
    clsAlphaColor.Color = newColor
    RaiseEvent Change
End Sub

Public Function GetIdealSize() As Long
    If (m_IdealControlHeight <= 0) Then ReflowColorPanel
    GetIdealSize = m_IdealControlHeight
End Function

Public Sub SyncToIdealSize()
    If (m_IdealControlHeight <= 0) Then ReflowColorPanel
    ucSupport.RequestNewSize ucSupport.GetBackBufferWidth, m_IdealControlHeight
End Sub

Public Sub Reset()

    cboColorModel.ListIndex = 0
    cboDepthColor.ListIndex = 1
    cboDepthGrayscale.ListIndex = 1
    cboAlphaModel.ListIndex = 0
    
    sldColorCount.Value = 256
    sldAlphaCutoff.Value = PD_DEFAULT_ALPHA_CUTOFF
    clsAlphaColor.Color = RGB(255, 0, 255)
    
End Sub

'Get/Set all control settings as a single XML packet
Public Function GetAllSettings() As String

    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    'All entries use text to make it easier to pass changed/upgraded settings in the future
    Dim outputColorModel As String
    Select Case cboColorModel.ListIndex
        Case 0
            outputColorModel = "Auto"
        Case 1
            outputColorModel = "Color"
        Case 2
            outputColorModel = "Gray"
    End Select
    cParams.AddParam "ColorDepth_ColorModel", outputColorModel
    
    'Which color depth we write is contingent on the color model, as color and gray use different button strips.
    ' (Gray supports some depths that color does not, e.g. 1-bit and 4-bit.)
    Dim colorColorDepth As String, grayColorDepth As String, outputPaletteSize As String
    
    Select Case cboDepthColor.ListIndex
        Case 0
            colorColorDepth = "Color_HDR"
        Case 1
            colorColorDepth = "Color_Standard"
        Case 2
            colorColorDepth = "Color_Indexed"
    End Select
    
    cParams.AddParam "ColorDepth_ColorDepth", colorColorDepth
        
    Select Case cboDepthGrayscale.ListIndex
        Case 0
            grayColorDepth = "Gray_HDR"
        Case 1
            grayColorDepth = "Gray_Standard"
        Case 2
            grayColorDepth = "Gray_Monochrome"
    End Select
    
    cParams.AddParam "ColorDepth_GrayDepth", grayColorDepth
    
    If sldColorCount.IsValid Then outputPaletteSize = CStr(sldColorCount.Value) Else outputPaletteSize = "256"
    cParams.AddParam "ColorDepth_PaletteSize", outputPaletteSize
    
    'Next, we've got a bunch of possible alpha modes to deal with (uuuuuugh)
    Dim outputAlphaModel As String
    Select Case cboAlphaModel.ListIndex
        Case 0
            outputAlphaModel = "Auto"
        Case 1
            outputAlphaModel = "Full"
        Case 2
            outputAlphaModel = "ByCutoff"
        Case 3
            outputAlphaModel = "ByColor"
        Case 4
            outputAlphaModel = "None"
    End Select
    
    cParams.AddParam "ColorDepth_AlphaModel", outputAlphaModel
    If sldAlphaCutoff.IsValid Then cParams.AddParam "ColorDepth_AlphaCutoff", sldAlphaCutoff.Value Else cParams.AddParam "ColorDepth_AlphaCutoff", PD_DEFAULT_ALPHA_CUTOFF
    cParams.AddParam "ColorDepth_AlphaColor", clsAlphaColor.Color
    
    GetAllSettings = cParams.GetParamString()
    
End Function

'Used by the "last-used settings" manager to reset all settings to the user's previous value(s)
Public Sub SetAllSettings(ByVal newSettings As String)

    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString newSettings
    
    Dim srcParam As String
    srcParam = cParams.GetString("ColorDepth_ColorModel", "Auto")
    
    If ParamsEqual(srcParam, "Color") Then
        cboColorModel.ListIndex = 1
    ElseIf ParamsEqual(srcParam, "Gray") Then
        cboColorModel.ListIndex = 2
    Else
        cboColorModel.ListIndex = 0
    End If
    
    srcParam = cParams.GetString("ColorDepth_ColorDepth", "Color_Standard")
    
    If ParamsEqual(srcParam, "Color") Then
        cboColorModel.ListIndex = 1
    ElseIf ParamsEqual(srcParam, "Gray") Then
        cboColorModel.ListIndex = 2
    Else
        cboColorModel.ListIndex = 0
    End If
    
    srcParam = cParams.GetString("ColorDepth_ColorDepth", "Color_Standard")
    
    If ParamsEqual(srcParam, "Color_HDR") Then
        cboDepthColor.ListIndex = 0
    ElseIf ParamsEqual(srcParam, "Color_Indexed") Then
        cboDepthColor.ListIndex = 2
    Else
        cboDepthColor.ListIndex = 1
    End If
    
    srcParam = cParams.GetString("ColorDepth_GrayDepth", "Gray_Standard")
    
    If ParamsEqual(srcParam, "Gray_HDR") Then
        cboDepthGrayscale.ListIndex = 0
    ElseIf ParamsEqual(srcParam, "Gray_Monochrome") Then
        cboDepthGrayscale.ListIndex = 2
    Else
        cboDepthGrayscale.ListIndex = 1
    End If
    
    sldColorCount.Value = cParams.GetLong("ColorDepth_PaletteSize", 256)
    
    srcParam = cParams.GetString("ColorDepth_AlphaModel", "Auto")
    
    If ParamsEqual(srcParam, "Full") Then
        cboAlphaModel.ListIndex = 1
    ElseIf ParamsEqual(srcParam, "ByCutoff") Then
        cboAlphaModel.ListIndex = 2
    ElseIf ParamsEqual(srcParam, "ByColor") Then
        cboAlphaModel.ListIndex = 3
    ElseIf ParamsEqual(srcParam, "None") Then
        cboAlphaModel.ListIndex = 4
    Else
        cboAlphaModel.ListIndex = 0
    End If
    
    sldAlphaCutoff.Value = cParams.GetLong("ColorDepth_AlphaCutoff")
    clsAlphaColor.Color = cParams.GetLong("ColorDepth_AlphaColor")
    
End Sub

Private Function ParamsEqual(ByVal param1 As String, ByVal param2 As String) As Boolean
    ParamsEqual = CBool(StrComp(LCase$(param1), LCase$(param2), vbBinaryCompare) = 0)
End Function

'To support high-DPI settings properly, we expose specialized move+size functions
Public Function GetLeft() As Long
    GetLeft = ucSupport.GetControlLeft
End Function

Public Sub SetLeft(ByVal newLeft As Long)
    ucSupport.RequestNewPosition newLeft, , True
End Sub

Public Function GetTop() As Long
    GetTop = ucSupport.GetControlTop
End Function

Public Sub SetTop(ByVal newTop As Long)
    ucSupport.RequestNewPosition , newTop, True
End Sub

Public Function GetWidth() As Long
    GetWidth = ucSupport.GetControlWidth
End Function

Public Sub SetWidth(ByVal newWidth As Long)
    ucSupport.RequestNewSize newWidth, , True
End Sub

Public Function GetHeight() As Long
    GetHeight = ucSupport.GetControlHeight
End Function

Public Sub SetHeight(ByVal newHeight As Long)
    ucSupport.RequestNewSize , newHeight, True
End Sub

Public Sub SetPositionAndSize(ByVal newLeft As Long, ByVal newTop As Long, ByVal newWidth As Long, ByVal newHeight As Long)
    ucSupport.RequestFullMove newLeft, newTop, newWidth, newHeight, True
End Sub

Private Sub cboAlphaModel_Click()
    RaiseEvent ColorSelectionRequired(CBool(cboAlphaModel.ListIndex = 3))
    UpdateTransparencyOptions
    RaiseEvent Change
End Sub

Private Sub cboColorModel_Click()
    UpdateColorDepthVisibility
    RaiseEvent Change
End Sub

Private Sub cboDepthColor_Click()
    UpdateColorDepthOptions
    RaiseEvent Change
End Sub

Private Sub cboDepthGrayscale_Click()
    UpdateColorDepthOptions
    RaiseEvent Change
End Sub

Private Sub clsAlphaColor_ColorChanged()
    RaiseEvent Change
End Sub

Private Sub sldAlphaCutoff_Change()
    RaiseEvent Change
End Sub

Private Sub sldColorCount_Change()
    RaiseEvent Change
End Sub

Private Sub ucSupport_GotFocusAPI()
    RaiseEvent GotFocusAPI
End Sub

Private Sub ucSupport_LostFocusAPI()
    RaiseEvent LostFocusAPI
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout
    RedrawBackBuffer
End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    UpdateControlLayout
End Sub

Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd
    
    'Color model and color depth are closely related; populate all button strips, then show/hide the relevant pairings
    cboColorModel.AddItem "auto", 0
    cboColorModel.AddItem "color", 1
    cboColorModel.AddItem "grayscale", 2
    cboColorModel.ListIndex = 0
    
    cboDepthColor.AddItem "HDR", 0
    cboDepthColor.AddItem "standard", 1
    cboDepthColor.AddItem "indexed", 2
    cboDepthColor.ListIndex = 1
    
    cboDepthGrayscale.AddItem "HDR", 0
    cboDepthGrayscale.AddItem "standard", 1
    cboDepthGrayscale.AddItem "monochrome", 2
    cboDepthGrayscale.ListIndex = 1
    
    UpdateColorDepthVisibility
    
    'PNGs also support a (ridiculous) amount of alpha settings
    cboAlphaModel.AddItem "auto", 0
    cboAlphaModel.AddItem "full", 1
    cboAlphaModel.AddItem "binary (by cut-off)", 2
    cboAlphaModel.AddItem "binary (by color)", 3
    cboAlphaModel.AddItem "none", 4
    cboAlphaModel.ListIndex = 0
    
    sldAlphaCutoff.NotchValueCustom = PD_DEFAULT_ALPHA_CUTOFF
    
    UpdateColorDepthVisibility
    UpdateTransparencyOptions
    ReflowColorPanel
    
    'Update the control size parameters at least once
    UpdateControlLayout
    
End Sub

'At run-time, painting is handled by the support class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_Resize()
    If (Not g_IsProgramRunning) Then ucSupport.RequestRepaint True
End Sub

Private Sub UpdateColorDepthVisibility()

    Select Case cboColorModel.ListIndex
    
        'Auto
        Case 0
            cboDepthColor.Visible = False
            cboDepthGrayscale.Visible = False
        
        'Color
        Case 1
            cboDepthColor.Visible = True
            cboDepthGrayscale.Visible = False
        
        'Grayscale
        Case 2
            cboDepthColor.Visible = False
            cboDepthGrayscale.Visible = True
    
    End Select

    UpdateColorDepthOptions

End Sub

Private Sub UpdateColorDepthOptions()
    
    'Indexed color modes allow for variable palette sizes
    If (cboDepthColor.Visible) Then
        sldColorCount.Visible = CBool(cboDepthColor.ListIndex = 2)
        lblColorCount.Visible = sldColorCount.Visible
    
    'Indexed grayscale mode also allows for variable palette sizes
    ElseIf (cboDepthGrayscale.Visible) Then
        sldColorCount.Visible = CBool(cboDepthGrayscale.ListIndex = 1)
        lblColorCount.Visible = sldColorCount.Visible
    
    'Other modes do not expose palette settings
    Else
        sldColorCount.Visible = False
        lblColorCount.Visible = False
    End If
    
    ReflowColorPanel
    
End Sub

Private Sub UpdateTransparencyOptions()
    
    Select Case cboAlphaModel.ListIndex
    
        'auto, full alpha
        Case 0, 1
            sldAlphaCutoff.Visible = False
            clsAlphaColor.Visible = False
            If g_IsProgramRunning Then RaiseEvent ColorSelectionRequired(False)
            
        'alpha by cut-off
        Case 2
            sldAlphaCutoff.Visible = True
            clsAlphaColor.Visible = False
            If g_IsProgramRunning Then RaiseEvent ColorSelectionRequired(False)
        
        'alpha by color
        Case 3
            sldAlphaCutoff.Visible = False
            clsAlphaColor.Visible = True
            If g_IsProgramRunning Then RaiseEvent ColorSelectionRequired(True)
            
        'no alpha
        Case 4
            sldAlphaCutoff.Visible = False
            clsAlphaColor.Visible = False
            If g_IsProgramRunning Then RaiseEvent ColorSelectionRequired(False)
    
    End Select
    
    ReflowColorPanel
    
End Sub

'Reflow various controls contingent on their visibility.  Note that this function *does not* show or hide controls;
' instead, it relies on functions like UpdateColorDepthVisibility() to do that in advance.
Private Sub ReflowColorPanel()

    Dim curHeight As Long
    curHeight = ucSupport.GetBackBufferHeight
    
    Dim yOffset As Long, yPadding As Long
    yOffset = cboColorModel.GetTop + cboColorModel.GetHeight
    yPadding = FixDPI(8)
    yOffset = yOffset + yPadding
    
    If cboDepthColor.Visible Then
        cboDepthColor.SetTop yOffset
        yOffset = yOffset + cboDepthColor.GetHeight + yPadding
    ElseIf cboDepthGrayscale.Visible Then
        cboDepthGrayscale.SetTop yOffset
        yOffset = yOffset + cboDepthGrayscale.GetHeight + yPadding
    End If
    
    If sldColorCount.Visible Then
        sldColorCount.SetTop yOffset
        lblColorCount.SetTop (sldColorCount.GetTop + sldColorCount.GetHeight) - lblColorCount.GetHeight
        yOffset = yOffset + sldColorCount.GetHeight + yPadding
    End If
    
    cboAlphaModel.SetTop yOffset
    yOffset = yOffset + cboAlphaModel.GetHeight + yPadding
    
    If sldAlphaCutoff.Visible Then
        sldAlphaCutoff.SetTop yOffset
        yOffset = yOffset + sldAlphaCutoff.GetHeight + yPadding
    ElseIf clsAlphaColor.Visible Then
        clsAlphaColor.SetTop yOffset
        yOffset = yOffset + clsAlphaColor.GetHeight + yPadding
    End If
    
    m_IdealControlHeight = yOffset
    RaiseEvent SizeChanged
    
End Sub

'Whenever a control property changes that affects control size or layout (including internal changes, like caption adjustments),
' call this function to recalculate the control's internal layout
Private Sub UpdateControlLayout()
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Sync all widths to match the current buffer width
    cboColorModel.SetWidth bWidth - cboColorModel.GetLeft
    cboDepthColor.SetWidth bWidth - cboDepthColor.GetLeft
    cboDepthGrayscale.SetWidth bWidth - cboDepthGrayscale.GetLeft
    lblColorCount.SetWidth bWidth - lblColorCount.GetLeft
    cboAlphaModel.SetWidth bWidth - cboAlphaModel.GetLeft
    sldAlphaCutoff.SetWidth bWidth - sldAlphaCutoff.GetLeft
    clsAlphaColor.SetWidth bWidth - clsAlphaColor.GetLeft
    
    'As such, just repaint the control for now
    RedrawBackBuffer
    
End Sub

'Primary rendering function.  Note that ucSupport handles a number of rendering duties (like maintaining a back buffer for us).
Private Sub RedrawBackBuffer()
    
    'We can improve shutdown performance by ignoring redraw requests
    If g_ProgramShuttingDown Then
        If (g_Themer Is Nothing) Then Exit Sub
    End If
    
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    If g_IsProgramRunning Then
        
        Dim bufferDC As Long
        bufferDC = ucSupport.GetBackBufferDC(True, g_Themer.GetGenericUIColor(UI_Background))
        
    End If
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint
    
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme()
    
    If ucSupport.ThemeUpdateRequired Then
        
        'UpdateColorList
        If g_IsProgramRunning Then ucSupport.UpdateAgainstThemeAndLanguage
        
        'Manually update all sub-controls
        cboColorModel.UpdateAgainstCurrentTheme
        cboDepthColor.UpdateAgainstCurrentTheme
        cboDepthGrayscale.UpdateAgainstCurrentTheme
        sldColorCount.UpdateAgainstCurrentTheme
        lblColorCount.UpdateAgainstCurrentTheme
        cboAlphaModel.UpdateAgainstCurrentTheme
        clsAlphaColor.UpdateAgainstCurrentTheme
        sldAlphaCutoff.UpdateAgainstCurrentTheme
        
    End If
    
End Sub