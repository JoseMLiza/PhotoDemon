Attribute VB_Name = "File_Menu"
'***************************************************************************
'File Menu Handler
'Copyright �2001-2013 by Tanner Helland
'Created: 15/Apr/01
'Last updated: 18/November/12
'Last update: common dialog file format string is now generated by the g_ImageFormats class (of type pdFormats)
'
'Functions for controlling standard file menu options.  Currently only handles "open image" and "save image".
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://www.tannerhelland.com/photodemon/#license
'
'***************************************************************************

Option Explicit

'This subroutine loads an image - note that the interesting stuff actually happens in PhotoDemon_OpenImageDialog, below
Public Sub MenuOpen()
    
    'String returned from the common dialog wrapper
    Dim sFile() As String
    
    If PhotoDemon_OpenImageDialog(sFile, FormMain.hWnd) Then PreLoadImage sFile

    Erase sFile

End Sub

'Pass this function a string array, and it will fill it with a list of files selected by the user.
' The commondialog filters are automatically set according to image formats supported by the program.
Public Function PhotoDemon_OpenImageDialog(ByRef listOfFiles() As String, ByVal ownerhWnd As Long) As Boolean

    'Common dialog interface
    Dim CC As cCommonDialog
    
    'Get the last "open image" path from the preferences file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPref_String("Program Paths", "OpenImage", "")
    
    Set CC = New cCommonDialog
        
    Dim sFileList As String
    
    'Use Steve McMahon's excellent Common Dialog class to launch a dialog (this way, no OCX is required)
    If CC.VBGetOpenFileName(sFileList, , True, True, False, True, g_ImageFormats.getCommonDialogInputFormats, g_LastOpenFilter, tempPathString, g_Language.TranslateMessage("Open an image"), , ownerhWnd, 0) Then
        
        'Message "Preparing to load image..."
        
        'Take the return string (a null-delimited list of filenames) and split it out into a string array
        listOfFiles = Split(sFileList, vbNullChar)
        
        Dim x As Long
        
        'Due to the buffering required by the API call, uBound(listOfFiles) should ALWAYS > 0 but
        ' let's check it anyway (just to be safe)
        If UBound(listOfFiles) > 0 Then
        
            'Remove all empty strings from the array (which are a byproduct of the aforementioned buffering)
            For x = UBound(listOfFiles) To 0 Step -1
                If listOfFiles(x) <> "" Then Exit For
            Next
            
            'With all the empty strings removed, all that's left is legitimate file paths
            ReDim Preserve listOfFiles(0 To x) As String
            
        End If
        
        'If multiple files were selected, we need to do some additional processing to the array
        If UBound(listOfFiles) > 0 Then
        
            'The common dialog function returns a unique array. Index (0) contains the folder path (without a
            ' trailing backslash), so first things first - add a trailing backslash
            Dim imagesPath As String
            imagesPath = FixPath(listOfFiles(0))
            
            'The remaining indices contain a filename within that folder.  To get the full filename, we must
            ' append the path from (0) to the start of each filename.  This will relieve the burden on
            ' whatever function called us - it can simply loop through the full paths, loading files as it goes
            For x = 1 To UBound(listOfFiles)
                listOfFiles(x - 1) = imagesPath & listOfFiles(x)
            Next x
            
            ReDim Preserve listOfFiles(0 To UBound(listOfFiles) - 1)
            
            'Save the new directory as the default path for future usage
            g_UserPreferences.SetPref_String "Program Paths", "OpenImage", imagesPath
            
        'If there is only one file in the array (e.g. the user only opened one image), we don't need to do all
        ' that extra processing - just save the new directory to the preferences file
        Else
        
            'Save the new directory as the default path for future usage
            tempPathString = listOfFiles(0)
            StripDirectory tempPathString
        
            g_UserPreferences.SetPref_String "Program Paths", "OpenImage", tempPathString
            
        End If
        
        'Also, remember the file filter for future use (in case the user tends to use the same filter repeatedly)
        g_UserPreferences.SetPref_Long "File Formats", "LastOpenFilter", g_LastOpenFilter
        
        'All done!
        PhotoDemon_OpenImageDialog = True
        
    'If the user cancels the commondialog box, simply exit out
    Else
        
        If CC.ExtendedError <> 0 Then pdMsgBox "An error occurred: %1", vbCritical + vbOKOnly + vbApplicationModal, "Common dialog error", CC.ExtendedError
    
        PhotoDemon_OpenImageDialog = False
    End If
    
    'Release the common dialog object
    Set CC = Nothing

End Function

'Subroutine for saving an image to file.  This function assumes the image already exists on disk and is simply
' being replaced; if the file does not exist on disk, this routine will automatically transfer control to Save As...
' The imageToSave is a reference to an ID in the pdImages() array.  It can be grabbed from the form.Tag value as well.
Public Function MenuSave(ByVal imageID As Long) As Boolean

    If pdImages(imageID).LocationOnDisk = "" Then
    
        'This image hasn't been saved before.  Launch the Save As... dialog
        MenuSave = MenuSaveAs(imageID)
        
    Else
    
        'This image has been saved before.
        
        Dim dstFilename As String
                
        'If the user has requested that we only save copies of current images, we need to come up with a new filename
        If g_UserPreferences.GetPref_Long("General Preferences", "SaveBehavior", 0) = 0 Then
            dstFilename = pdImages(imageID).LocationOnDisk
        Else
        
            'Determine the destination directory
            Dim tempPathString As String
            tempPathString = pdImages(imageID).LocationOnDisk
            StripDirectory tempPathString
            
            'Next, determine the target filename
            Dim tempFilename As String
            tempFilename = pdImages(imageID).OriginalFileName
            
            'Finally, determine the target file extension
            Dim tempExtension As String
            tempExtension = GetExtension(pdImages(imageID).LocationOnDisk)
            
            'Now, call the incrementFilename function to find a unique filename of the "filename (n+1)" variety
            dstFilename = tempPathString & incrementFilename(tempPathString, tempFilename, tempExtension) & "." & tempExtension
        
        End If
        
        'Check to see if the image is in a format that potentially provides an "additional settings" prompt.
        ' If it is, the user needs to be prompted at least once for those settings.
        
        'JPEG
        If (pdImages(imageID).CurrentFileFormat = FIF_JPEG) And (pdImages(imageID).hasSeenJPEGPrompt = False) Then
            MenuSave = PhotoDemon_SaveImage(pdImages(imageID), dstFilename, imageID, True)
        
        'JPEG-2000
        ElseIf (pdImages(imageID).CurrentFileFormat = FIF_JP2) And (pdImages(imageID).hasSeenJP2Prompt = False) Then
            MenuSave = PhotoDemon_SaveImage(pdImages(imageID), dstFilename, imageID, True)
        
        'All other formats
        Else
            MenuSave = PhotoDemon_SaveImage(pdImages(imageID), dstFilename, imageID, False, pdImages(imageID).saveParameters)
        End If
    End If

End Function

'Subroutine for displaying a commondialog save box, then saving an image to the specified file
Public Function MenuSaveAs(ByVal imageID As Long) As Boolean

    Dim CC As cCommonDialog
    Set CC = New cCommonDialog
    
    'Get the last "save image" path from the preferences file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPref_String("Program Paths", "SaveImage", "")
        
    'g_LastSaveFilter will be set to "-1" if the user has never saved a file before.  If that happens, default to JPEG
    If g_LastSaveFilter = -1 Then
    
        g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(FIF_JPEG) + 1
    
    'Otherwise, set g_LastSaveFilter to this image's current file format, or optionally the last-used format
    Else
    
        'There is a user preference for defaulting to either:
        ' 1) The current image's format (standard behavior)
        ' 2) The last format the user specified in the Save As screen (my preferred behavior)
        ' Use that preference to determine which save filter we select.
        If g_UserPreferences.GetPref_Long("General Preferences", "DefaultSaveFormat", 0) = 0 Then
        
            g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(pdImages(imageID).CurrentFileFormat) + 1
    
            'The user may have loaded a file format where INPUT is supported but OUTPUT is not.  If this happens,
            ' we need to suggest an alternative format.  Use the color-depth of the current image as our guide.
            If g_LastSaveFilter = -1 Then
            
                '24bpp layers default to JPEG
                If pdImages(imageID).mainLayer.getLayerColorDepth = 24 Then
                    g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(FIF_JPEG) + 1
                
                '32bpp layers default to PNG
                Else
                    g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(FIF_PNG) + 1
                End If
            
            End If
                    
        'Note that we don't need an "Else" here - the g_LastSaveFilter value will already be present
        End If
    
    End If
    
    'Check to see if an image with this filename appears in the save location. If it does, use the incrementFilename
    ' function to append ascending numbers (of the format "_(#)") to the filename until a unique filename is found.
    Dim sFile As String
    sFile = tempPathString & incrementFilename(tempPathString, pdImages(imageID).OriginalFileName, g_ImageFormats.getOutputFormatExtension(g_LastSaveFilter - 1))
        
    If CC.VBGetSaveFileName(sFile, , True, g_ImageFormats.getCommonDialogOutputFormats, g_LastSaveFilter, tempPathString, g_Language.TranslateMessage("Save an image"), g_ImageFormats.getCommonDialogDefaultExtensions, FormMain.hWnd, 0) Then
                
        'Store the selected file format to the image object
        pdImages(imageID).CurrentFileFormat = g_ImageFormats.getOutputFIF(g_LastSaveFilter - 1)
        
        'Save the new directory as the default path for future usage
        tempPathString = sFile
        StripDirectory tempPathString
        g_UserPreferences.SetPref_String "Program Paths", "SaveImage", tempPathString
        
        'Also, remember the file filter for future use (in case the user tends to use the same filter repeatedly)
        g_UserPreferences.SetPref_Long "File Formats", "LastSaveFilter", g_LastSaveFilter
                        
        'Transfer control to the core SaveImage routine, which will handle color depth analysis and actual saving
        MenuSaveAs = PhotoDemon_SaveImage(pdImages(imageID), sFile, imageID, True)
        
        'If the save was successful, update the associated window caption to reflect the new name and/or location
        If MenuSaveAs Then
            
            If g_UserPreferences.GetPref_Long("General Preferences", "ImageCaptionSize", 0) Then
                pdImages(imageID).containingForm.Caption = getFilename(sFile)
            Else
                pdImages(imageID).containingForm.Caption = sFile
            End If
            
        End If
        
    Else
        MenuSaveAs = False
    End If
    
    'Release the common dialog object
    Set CC = Nothing
    
End Function
