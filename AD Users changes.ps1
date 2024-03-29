#Requires -Version 5.1
#Requires -Modules ActiveDirectory, ImportExcel
#Requires -Modules Toolbox.ActiveDirectory, Toolbox.HTML, Toolbox.EventLog

<#
    .SYNOPSIS
        Monitor changes on AD user accounts and send an e-mail with a report.

    .DESCRIPTION
        When the script runs it always creates a single Excel file containing 
        all the active directory user accounts with their current state.
        - Ex. 2022-09-31 1030 - State{0}.xlsx

        The second step for the script is to compare the latest Excel file 
        (not the one from today) with the current AD user accounts and report
        the differences in a second Excel file.
        - Ex. 2022-09-31 1030 - Differences{0}.xlsx

        All required parameters for the script are ready from a .JSON file
        defined in '$ImportFile'.

        This script is intended to be executed as a scheduled task on a daily 
        or weekly basis. It wil then generate 'Differences{0}.xlsx' files when
        they occur.

    .PARAMETER ImportFile
        Contains all the required parameters to run the script. These parameters
        are explained below and an example can be found in file 'Example.json'.

    .PARAMETER AD.Include.Type
        Where to search for user accounts in the active directory.

        Valid values are:
        - OU    : Collection of organizational units
        - Group : Collection of groups

    .PARAMETER AD.Include.Name
        Depending on the selected Type, can be a collection of OU's or group 
        names.

    .PARAMETER AD.Exclude.OU
        Active directory user accounts that are located in one of the excluded 
        organizational units will be excluded from the search results.

    .PARAMETER AD.Property.ToMonitor
        Collection of active directory fields where to look for changes. All 
        other fields are disregarded.
        
        Wildcard '*' is supported and will monitor all active directory fields.

    .PARAMETER AD.Property.InReport
        Collection of active directory fields to export to the Excel file 
        'Differences{0}.xlsx' where the changes are stored.
        
        Wildcard '*' is supported and will report all active directory fields.

    .PARAMETER SendMail.Header
        The header to use in the e-mail sent to the end user.

    .PARAMETER SendMail.To
        List of e-mail addresses where to send the e-mail too.

    .PARAMETER SendMail.When
        Determines when an e-mail is sent to the end user.
        Valid options:
        - OnlyWhenChangesAreFound : when no changes are found no e-mail is sent
        - Always                  : always sent an e-mail, even when no changes 
                                    are found
#>

[CmdLetBinding()]
Param (
    [Parameter(Mandatory)]
    [String]$ScriptName,
    [Parameter(Mandatory)]
    [String]$ImportFile,
    [String]$LogFolder = "$env:POWERSHELL_LOG_FOLDER\AD Reports\AD Users changes\$ScriptName",
    [String[]]$ScriptAdmin = @(
        $env:POWERSHELL_SCRIPT_ADMIN,
        $env:POWERSHELL_SCRIPT_ADMIN_BACKUP
    )
)

Begin {
    Try {
        $now = Get-ScriptRuntimeHC -Start
        Import-EventLogParamsHC -Source $ScriptName
        Write-EventLog @EventStartParams
        $Error.Clear()

        #region Logging
        try {
            $logParams = @{
                LogFolder    = New-Item -Path $LogFolder -ItemType 'Directory' -Force -ErrorAction 'Stop'
                Name         = $ScriptName
                Date         = 'ScriptStartTime'
                Format       = 'yyyy-MM-dd HHmmss (DayOfWeek)'
                NoFormatting = $true
            }
            $logFile = New-LogFileNameHC @logParams
        }
        Catch {
            throw "Failed creating the log folder '$LogFolder': $_"
        }
        #endregion

        try {
            $adProperties = @(
                @{
                    Name       = 'AccountExpirationDate'
                    Expression = { $_.AccountExpirationDate } 
                },
                @{
                    Name       = 'Country'
                    Expression = { $_.co } 
                },
                @{
                    Name       = 'Company'
                    Expression = { $_.Company } 
                },
                @{
                    Name       = 'Department'
                    Expression = { $_.Department } 
                },
                @{
                    Name       = 'Description'
                    Expression = { $_.Description } 
                },
                @{
                    Name       = 'DisplayName'
                    Expression = { $_.DisplayName } 
                },
                @{
                    Name       = 'EmailAddress'
                    Expression = { $_.EmailAddress } 
                },
                @{
                    Name       = 'EmployeeID'
                    Expression = { $_.EmployeeID } 
                },
                @{
                    Name       = 'EmployeeType'
                    Expression = { $_.EmployeeType } 
                },
                @{
                    Name       = 'Enabled'
                    Expression = { $_.Enabled } 
                },
                @{
                    Name       = 'Fax'
                    Expression = { $_.Fax } 
                },
                @{
                    Name       = 'FirstName'
                    Expression = { $_.GivenName } 
                }, 
                @{
                    Name       = 'HeidelbergCementBillingID'
                    Expression = { $_.extensionAttribute8 } 
                },
                @{
                    Name       = 'HomePhone'
                    Expression = { $_.HomePhone } 
                },
                @{
                    Name       = 'HomeDirectory'
                    Expression = { $_.HomeDirectory } 
                },
                @{
                    Name       = 'IpPhone'
                    Expression = { $_.IpPhone } 
                },
                @{
                    Name       = 'LastName'
                    Expression = { $_.Surname } 
                }, 
                @{
                    Name       = 'LastLogonDate'
                    Expression = { $_.LastLogonDate } 
                }, 
                @{
                    Name       = 'LockedOut'
                    Expression = { $_.LockedOut } 
                }, 
                @{
                    Name       = 'Manager'
                    Expression = { 
                        if ($_.manager) { Get-ADDisplayNameHC $_.manager }
                    }
                }, 
                @{
                    Name       = 'MobilePhone'
                    Expression = { $_.MobilePhone } 
                }, 
                @{
                    Name       = 'Name'
                    Expression = { $_.Name } 
                }, 
                @{
                    Name       = 'Notes'
                    Expression = { $_.info -replace "`n", ' ' } 
                },
                @{
                    Name       = 'Office'
                    Expression = { $_.Office } 
                }, 
                @{
                    Name       = 'OfficePhone'
                    Expression = { $_.OfficePhone } 
                }, 
                @{
                    Name       = 'OU'
                    Expression = {
                        ConvertTo-OuNameHC $_.CanonicalName
                    }
                },
                @{
                    Name       = 'Pager'
                    Expression = { $_.Pager } 
                }, 
                @{
                    Name       = 'PasswordExpired'
                    Expression = { $_.PasswordExpired } 
                }, 
                @{
                    Name       = 'PasswordNeverExpires'
                    Expression = { $_.PasswordNeverExpires } 
                }, 
                @{
                    Name       = 'SamAccountName'
                    Expression = { $_.SamAccountName } 
                }, 
                @{
                    Name       = 'LogonScript'
                    Expression = { $_.scriptPath } 
                }, 
                @{
                    Name       = 'Title'
                    Expression = { $_.Title } 
                }, 
                @{
                    Name       = 'TSAllowLogon'
                    Expression = {
                        Get-ADTsProfileHC $_.DistinguishedName 'AllowLogon'
                    }
                },
                @{
                    Name       = 'TSHomeDirectory'
                    Expression = { 
                        Get-ADTsProfileHC $_.DistinguishedName 'HomeDirectory' 
                    }
                }, 
                @{
                    Name       = 'TSHomeDrive'
                    Expression = {
                        Get-ADTsProfileHC $_.DistinguishedName 'HomeDrive'
                    }
                }, 
                @{
                    Name       = 'TSUserProfile'
                    Expression = {
                        Get-ADTsProfileHC $_.DistinguishedName 'UserProfile' 
                    } 
                },
                @{
                    Name       = 'UserPrincipalName'
                    Expression = { $_.UserPrincipalName } 
                }, 
                @{
                    Name       = 'WhenChanged'
                    Expression = { $_.WhenChanged } 
                }, 
                @{
                    Name       = 'WhenCreated'
                    Expression = { $_.WhenCreated } 
                }
            )

            #region Import .json file
            $M = "Import .json file '$ImportFile'"
            Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M

            $file = Get-Content $ImportFile -Raw -EA Stop | ConvertFrom-Json
            #endregion

            #region Test .json file
            if (-not ([array]$adPropertyToMonitor = $file.AD.Property.ToMonitor)) {
                throw "Property 'AD.Property.ToMonitor' not found."
            }
            if ($adPropertyToMonitor -ne '*') {
                $adPropertyToMonitor | Where-Object { 
                    $adProperties.Name -notContains $_ 
                } | ForEach-Object {
                    throw "Property '$_' defined in 'AD.Property.ToMonitor' is not a valid AD property. Valid AD properties are: $($adProperties.Name)"
                }
            }
            if (-not ([array]$adPropertyInReport = $file.AD.Property.InReport)) {
                throw "Property 'AD.Property.InReport' not found."
            }
            if ($adPropertyInReport -ne '*') {
                $adPropertyInReport | Where-Object { 
                    $adProperties.Name -notContains $_ 
                } | ForEach-Object {
                    throw "Property '$_' defined in 'AD.Property.InReport' is not a valid AD property. Valid AD properties are: $($adProperties.Name)"
                }
            }
            if (-not ($adIncludeType = $file.AD.Include.Type)) {
                throw "Property 'AD.Include.Type' not found."
            }
            if ($adIncludeType -notMatch '^OU$|^Group$') {
                throw "Property 'AD.Include.Type' has the incorrect value '$($adIncludeType)'. Valid options are 'OU' or 'Group'."
            }
            if (-not ($adIncludeName = $file.AD.Include.Name)) {
                throw "Property 'AD.Include.Name' not found."
            }
            if ($adIncludeType -eq 'OU') {
                $adIncludeName | 
                Where-Object { -not (Test-ADOuExistsHC -Name $_) } | 
                ForEach-Object {
                    throw "OU '$_' defined in 'AD.Include.Name' does not exist"
                }
            }
            else {
                $adIncludeName | 
                Where-Object { 
                    -not (Get-ADGroup -Filter "Name -EQ '$_'" -EA Ignore ) 
                } | 
                ForEach-Object {
                    throw "Group '$_' defined in 'AD.Include.Name' does not exist"
                }
            }
            if (-not ($mailTo = $file.SendMail.To)) {
                throw "Property 'SendMail.To' not found."
            }
            if (-not ($mailWhen = $file.SendMail.When)) {
                throw "Property 'SendMail.When' not found."
            }
            if (
                $mailWhen -notMatch '^Always$|^OnlyWhenChangesAreFound$'
            ) {
                throw "The value '$mailWhen' in 'SendMail.When' is not supported. Only the value 'Always' or 'OnlyWhenChangesAreFound' can be used."
            }
            #endregion

            #region Convert excluded OU's to match Excel file format
            $adExcludeOu = $file.AD.Exclude.OU | Where-Object { $_ } | 
            ForEach-Object {
                $M = "Ignore OU '{0}'" -f $_
                Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M

                if (-not (Test-ADOuExistsHC -Name $_)) {
                    throw "OU '$_' defined in 'AD.Exclude.OU' does not exist"
                }
                ConvertTo-OuNameHC -OU $_
            }
            #endregion

            #region Remove always changing properties from properties to monitor
            if ($adPropertyToMonitor -eq '*') {
                $adPropertyToMonitor = $adProperties.Name | Where-Object {
                    @(
                        'LastLogonDate', 'PasswordExpired',
                        'WhenChanged', 'WhenCreated'
                    ) -notContains $_
                }
            }
            #endregion
            
            #region Add missing monitoring properties to Excel differences file
            if ($adPropertyInReport -ne '*') {
                foreach ($p in $adPropertyToMonitor) {
                    if ($adPropertyInReport -notContains $p) {
                        $adPropertyInReport += $p
                    }   
                }
            }
            #endregion

            $mailParams = @{
                To        = $mailTo
                Bcc       = $ScriptAdmin
                Priority  = 'Normal'
                LogFolder = $logParams.LogFolder
                Header    = $ScriptName 
                Save      = "$logFile - Mail.html"
            }
        }
        catch {
            throw "Failed to import file '$ImportFile': $_"
        }
    }
    Catch {
        Write-Warning $_
        Send-MailHC -To $ScriptAdmin -Subject 'FAILURE' -Priority 'High' -Message $_ -Header $ScriptName
        Write-EventLog @EventErrorParams -Message "FAILURE:`n`n- $_"
        Write-EventLog @EventEndParams; Exit 1
    }
}
Process {
    Try {
        #region Get previously exported AD users
        $M = "Get previously exported AD users from the latest Excel file in folder '{0}'" -f $logParams.LogFolder
        Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M

        $params = @{
            LiteralPath = $logParams.LogFolder
            Filter      = '* - State.xlsx'
            File        = $true
        }
        $lastExcelFile = Get-ChildItem @params | 
        Sort-Object 'CreationTime' | Select-Object -Last 1

        $previousAdUsers = @()

        if ($lastExcelFile) {
            $params = @{
                Path        = $lastExcelFile.FullName
                ErrorAction = 'Stop'
            }
            $previousAdUsers += Import-Excel @params | Where-Object {
                $adExcludeOu -notContains $_.OU
            }

            $M = "Found {0} AD user account{1} in Excel file '{2}'" -f 
            $previousAdUsers.Count, 
            $(if ($previousAdUsers.Count -ne 1) { 's' }),
            $lastExcelFile.FullName
            Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M
        }
        #endregion

        #region Get current AD users
        $currentAdUsers = if ($adIncludeType -eq 'OU') {
            foreach ($ou in $adIncludeName) {
                $M = "Get user accounts in OU '$ou'"
                Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M

                Get-ADUser -SearchBase $ou -Filter '*' -Properties @(
                    'AccountExpirationDate', 'CanonicalName', 'Co', 'Company', 
                    'Department', 'Description', 'DisplayName', 
                    'DistinguishedName', 'EmailAddress', 'EmployeeID', 
                    'EmployeeType', 'Enabled', 'ExtensionAttribute8', 'Fax', 
                    'GivenName', 'HomePhone', 'HomeDirectory', 'Info', 'IpPhone', 
                    'Surname', 'LastLogonDate', 'LockedOut', 'Manager', 
                    'MobilePhone', 'Name', 'Office', 'OfficePhone', 'Pager', 
                    'PasswordExpired', 'PasswordNeverExpires', 'SamAccountName', 
                    'ScriptPath', 'Title', 'UserPrincipalName', 'WhenChanged' , 
                    'WhenCreated'
                )
            }
        }
        else {
            foreach ($group in $adIncludeName) {
                $M = "Get user accounts in group '$group'"
                Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M

                Get-ADGroupMember -Identity $group -Recursive | 
                Get-ADUser -Properties @(
                    'AccountExpirationDate', 'CanonicalName', 'Co', 'Company', 
                    'Department', 'Description', 'DisplayName', 
                    'DistinguishedName', 'EmailAddress', 'EmployeeID', 
                    'EmployeeType', 'Enabled', 'ExtensionAttribute8', 'Fax', 
                    'GivenName', 'HomePhone', 'HomeDirectory', 'Info', 'IpPhone', 
                    'Surname', 'LastLogonDate', 'LockedOut', 'Manager', 
                    'MobilePhone', 'Name', 'Office', 'OfficePhone', 'Pager', 
                    'PasswordExpired', 'PasswordNeverExpires', 'SamAccountName', 
                    'ScriptPath', 'Title', 'UserPrincipalName', 'WhenChanged' , 
                    'WhenCreated'
                )
            }
        }

        [array]$currentAdUsers = $currentAdUsers | 
        Sort-Object -Unique -Property 'SamAccountName' | 
        Select-Object -Property $adProperties | 
        Where-Object { $adExcludeOu -notContains $_.OU }

        $M = 'Found {0} user account{1} in AD' -f $currentAdUsers.Count,
        $(if ($currentAdUsers.Count -ne 1) { 's' })
        Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M

        if (-not $currentAdUsers) {
            throw 'No AD user accounts found'
        }
        #endregion

        #region Export current AD users to Excel file
        $excelParams = @{
            Path          = "$logFile - State.xlsx"
            WorksheetName = 'AllUsers'
            TableName     = 'AllUsers'
            AutoSize      = $true
            FreezeTopRow  = $true
            Verbose       = $false
        }

        $M = "Export {0} row{1} to Excel file '{2}'" -f 
        $currentAdUsers.Count, $(if ($currentAdUsers.Count -ne 1) { 's' }), 
        $excelParams.Path
        Write-Verbose $M; Write-EventLog @EventOutParams -Message $M

        $currentAdUsers | Export-Excel @excelParams
        #endregion

        if (-not $previousAdUsers) {
            # wait 1 second to ensure we have a unique log file name
            # in case the script runs immediately again
            # this is an edge case scenario
            Start-Sleep -Seconds 1

            $M = 'No comparison possible because there is no previously exported Excel file with AD user accounts yet. The next run will not have this issue because a snapshot of the current AD users has just been created and exported to Excel. This file will then be used for comparison on the next run.'
            Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M
            Write-EventLog @EventEndParams; Exit
        }

        #region Compare AD
        #region Import current AD users again for comparing equality
        $params = @{
            Path          = $excelParams.Path
            WorksheetName = $excelParams.WorksheetName
            ErrorAction   = 'Stop'
        }
        [Array]$currentAdUsers = Import-Excel @params
        #endregion

        #region Verbose
        $M = 'Compare {0} previous user{1} with {2} current user{3}' -f 
        $previousAdUsers.Count, $(if ($previousAdUsers.Count -ne 1) { 's' }),
        $currentAdUsers.Count, $(if ($currentAdUsers.Count -ne 1) { 's' })
        Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M
        #endregion

        $differencesAdUsers = @()

        #region Find added and removed users
        $params = @{
            ReferenceObject  = $currentAdUsers
            DifferenceObject = $previousAdUsers
            Property         = 'SamAccountName'
        }
        $diffSamAccounts = Compare-Object @params

        $differencesAdUsers += Foreach ($d in $diffSamAccounts) {
            Switch ($d.SideIndicator) {
                '=>' {
                    #region User no longer in AD
                    $M = "User '{0}' removed from AD" -f $d.SamAccountName
                    Write-Verbose $M
                    Write-EventLog @EventOutParams -Message $M

                    $previousAdUsers.Where(
                        { $_.SamAccountName -eq $d.SamAccountName },
                        'First', 1
                    ) | 
                    Select-Object -Property *, @{
                        Name       = 'Status'
                        Expression = { 'REMOVED' }
                    }, 
                    @{
                        Name       = 'UpdatedFields'
                        Expression = { $null }
                    }
                    #endregion
                }
                '<=' {
                    #region New user
                    $M = "User '{0}' added to AD" -f $d.SamAccountName
                    Write-Verbose $M
                    Write-EventLog @EventOutParams -Message $M

                    $currentAdUsers.Where(
                        { $_.SamAccountName -eq $d.SamAccountName },
                        'First', 1
                    ) | 
                    Select-Object -Property *, @{
                        Name       = 'Status'
                        Expression = { 'ADDED' }
                    },
                    @{
                        Name       = 'UpdatedFields'
                        Expression = { $null }
                    }
                    #endregion
                }
            }
        }
        #endregion

        #region Find updated users
        $differencesAdUsers += foreach ($currentAdUser in $currentAdUsers) {
            $previousAdUser = $previousAdUsers.Where(
                { $_.SamAccountName -eq $currentAdUser.SamAccountName }, 
                'First', 1
            )

            if (-not $previousAdUser) { Continue }

            $propertiesUpdated = @()
            foreach ($p in $adPropertyToMonitor) {
                if ($currentAdUser.$p -ne $previousAdUser.$p) {
                    $M = "User '{0}' property '{1}' updated from '{2}' to '{3}'" -f 
                    $currentAdUser.SamAccountName, $p,
                    $previousAdUser.$p, $currentAdUser.$p
                    Write-Verbose $M
                    Write-EventLog @EventOutParams -Message $M

                    $propertiesUpdated += $p
                }
            }

            if ($propertiesUpdated) {
                $previousAdUsers.Where(
                    { $_.SamAccountName -eq $currentAdUser.SamAccountName },
                    'First', 1
                ) | 
                Select-Object -Property *, @{
                    Name       = 'Status'
                    Expression = { 'UPDATED_BEFORE' }
                }, @{
                    Name       = 'UpdatedFields'
                    Expression = { $propertiesUpdated }
                }

                $currentAdUser | 
                Select-Object -Property *, @{
                    Name       = 'Status'
                    Expression = { 'UPDATED_AFTER' }
                }, @{
                    Name       = 'UpdatedFields'
                    Expression = { $propertiesUpdated }
                }
            }
        }
        #endregion

        $M = 'Found {0} difference{1}' -f $differencesAdUsers.Count, $(
            if ($differencesAdUsers.Count -ne 1) { 's' }
        )
        Write-Verbose $M; Write-EventLog @EventVerboseParams -Message $M
        #endregion

        #region Export differences between previous and current AD users
        if ($differencesAdUsers) {
            $excelDifferencesParams = @{
                Path          = "$logFile - Differences.xlsx"
                WorksheetName = 'Differences'
                TableName     = 'Differences'
                AutoSize      = $true
                FreezeTopRow  = $true
                Verbose       = $false
            }

            #region Verbose
            $M = "Export {0} row{1} to Excel file '{2}'" -f 
            $differencesAdUsers.Count, 
            $(if ($differencesAdUsers.Count -ne 1) { 's' }),
            $excelDifferencesParams.Path
            Write-Verbose $M; Write-EventLog @EventOutParams -Message $M
            #endregion

            #region Order properties
            $selectParams = @{
                Property        = (
                    @(
                        @{
                            Name       = 'Status'
                            Expression = { $_.Status }
                        }
                        @{
                            Name       = 'UpdatedFields'
                            Expression = { $_.UpdatedFields -join ', ' }
                        }
                        @{
                            Name       = 'SamAccountName'
                            Expression = { $_.SamAccountName }
                        }
                    ) + $adPropertyInReport
                )
                ExcludeProperty = @('Status', 'UpdatedFields', 'SamAccountName')
            }
            #endregion

            $differencesAdUsers | Select-Object @selectParams | 
            Export-Excel @excelDifferencesParams

            $mailParams.Attachments = $excelDifferencesParams.Path
        }
        #endregion
    }
    Catch {
        Write-Warning $_
        Send-MailHC -To $ScriptAdmin -Subject 'FAILURE' -Priority 'High' -Message $_ -Header $ScriptName
        Write-EventLog @EventErrorParams -Message "FAILURE:`n`n- $_"
        Write-EventLog @EventEndParams; Exit 1
    }
}
End {
    Try {
        if (($mailWhen -eq 'Always') -or ($differencesAdUsers)) {
            $counter = @{
                currentUsers  = $currentAdUsers.Count
                previousUsers = $previousAdUsers.Count
                updatedUsers  = $differencesAdUsers.Where(
                    { $_.Status -eq 'UPDATED_AFTER' }).Count
                removedUsers  = $differencesAdUsers.Where(
                    { $_.Status -eq 'REMOVED' }).Count
                addedUsers    = $differencesAdUsers.Where(
                    { $_.Status -eq 'ADDED' }).Count
                errors        = $Error.Count
            }

            #region Subject and Priority
            $mailParams.Subject = if (
                (
                    $counter.updatedUsers + 
                    $counter.removedUsers + 
                    $counter.addedUsers
                ) -eq 0
            ) {
                'No changes detected'
            }
            else {
                '{0} added, {1} updated, {2} removed' -f $counter.addedUsers,
                $counter.updatedUsers, $counter.removedUsers
            }

            if ($counter.errors) {
                $mailParams.Priority = 'High'
                $mailParams.Subject += ', {0} error{1}' -f $counter.errors, $(
                    if ($counter.errors -ne 1) { 's' }
                )
            }
            #endregion

            #region Create html lists
            $htmlErrorList = if ($counter.errors) {
                "<p>Detected <b>{0} non terminating error{1}</b>:{2}</p>" -f $counter.errors, 
                $(
                    if ($counter.errors -ne 1) { 's' }
                ),
                $(
                    $Error.Exception.Message | Where-Object { $_ } | 
                    ConvertTo-HtmlListHC
                )
            }
            #endregion

            #region Send mail
            $htmlTable = "
            <table>
                <tr>
                    <th>{0}</th>
                    <td>{1}</td>
                </tr>
                <tr>
                    <th>{2}</th>
                    <td>{3}</td>
                </tr>
                <tr>
                    <th>Added</th>
                    <td>{4}</td>
                </tr>
                <tr>
                    <th>Updated</th>
                    <td>{5}</td>
                </tr>
                <tr>
                    <th>Removed</th>
                    <td>{6}</td>
                </tr>
            </table>" -f 
            $now.ToString('dd/MM/yyyy HH:mm'), $counter.currentUsers, 
            $lastExcelFile.CreationTime.ToString('dd/MM/yyyy HH:mm'), 
            $counter.previousUsers, $counter.addedUsers, $counter.updatedUsers, 
            $counter.removedUsers

            $mailParams.Message = "
            $htmlErrorList
            <p>AD user accounts:</p>
            $htmlTable
            {0}{1}" -f $(
                if ($mailParams.Attachments) {
                    '<p><i>* Check the attachment for details</i></p>'
                }
            ),
            $(
                if ($adIncludeType -eq 'OU') {
                    $adIncludeName | ConvertTo-OuNameHC -OU | Sort-Object |
                    ConvertTo-HtmlListHC -Header "$adIncludeType`:"
                }
                else {
                    $adIncludeName | Sort-Object |
                    ConvertTo-HtmlListHC -Header "$adIncludeType`:"
                }
            )
            
            $M = "Send mail`r`n- Header:`t{0}`r`n- To:`t`t{1}`r`n- Subject:`t{2}" -f 
            $mailParams.Header, $($mailParams.To -join ','), $mailParams.Subject
            Write-Verbose $M
            
            Get-ScriptRuntimeHC -Stop
            Send-MailHC @mailParams
            #endregion
        }
    }
    Catch {
        Write-Warning $_
        Send-MailHC -To $ScriptAdmin -Subject 'FAILURE' -Priority 'High' -Message $_ -Header $ScriptName
        Write-EventLog @EventErrorParams -Message "FAILURE:`n`n- $_"; Exit 1
    }
    Finally {
        Write-EventLog @EventEndParams
    }
}