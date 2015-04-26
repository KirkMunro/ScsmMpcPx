<#############################################################################
DESCRIPTION

Copyright 2015 Provance Technologies.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#############################################################################>

#region Initialize the module.

Invoke-Snippet -Name Module.Initialize

#endregion

# TODO: Consider verifying sn.exe is in the current path and verifying the authoring toolkit and other requirements are installed/available

#region Define the Management Pack Configuration DSL.

New-DomainSpecificLanguage -Name $PSModule.Name -Syntax {
    ManagementPackConfiguration Name {
        Properties {
            string Company
            string Copyright
            string DisplayName
            string Description
            Version Version
        }
        BuildOptions {
            string Location
            string IconPath
            string StrongNameKeyFile
            System.Security.Cryptography.X509Certificates.X509Certificate2 CodeSigningCertificate
        }
        AdminSettings {
            PropertyGroup Name {
                BooleanProperty Name {
                    string Label
                    string [HelpMessage]
                    boolean DefaultValue
                    boolean [Mandatory]
                }
                IntegerProperty Name {
                    string Label
                    string [HelpMessage]
                    int DefaultValue
                    int [MinValue]
                    int [MaxValue]
                    boolean [Mandatory]
                }
                StringProperty Name {
                    string Label
                    string [HelpMessage]
                    string DefaultValue
                    boolean [Mandatory]
                }
            }
        }
        Triggers {
            DailySchedule Name {
                string StartTime
                int DaysOfWeekMask
            }
            #Interval Name {
            #    string StartTime
            #    int Interval
            #    int [IntervalUnits]
            #}
            #ScsmEvent Name {
            #    string ClassName
            #    int EventType
            #}
        }
        Workflows {
            PowerShellScript Name {
                string DisplayName
                string Description
                string TriggerName
                scriptblock ScriptBlock
            }
            PowerShellScriptFile Name {
                string DisplayName
                string Description
                string TriggerName
                string Path
            }
            SmaRunbook Name {
                string DisplayName
                string Description
                string TriggerName
                string Endpoint
                string RunbookName
            }
        }
    }
}

#endregion

#region Define any special processing to be used when invoking the domain-specific language.

Register-DslKeywordEvent -DslName $PSModule.Name -KeywordPath ManagementPackConfiguration -Event OnInvoked -Action {
    try {
        # Assign the configuration to another variable so that we can access it anywhere in this event
        $mpc = $_

        # Get the SCSM installation folder
        $scsmInstallFolder = Get-ScsmPxInstallDirectory

        # Find the path to the latest sn.exe, preferring 64-bit if it is available
        $snExe = Get-Command -Name sn.exe -CommandType Application -ErrorAction Ignore `
            | Sort-Object -Property @{Expression={$_.FileVersionInfo.ProductVersion -as [System.Version]}} -Descending `
            | Select-Object -First 1
        if (-not $snExe) {
            $windowsSdkRegistryRoot = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Microsoft SDKs\Windows'
            if (Test-Path -LiteralPath $windowsSdkRegistryRoot -ErrorAction Ignore) {
                $snExe = Get-ItemProperty -Path "${windowsSdkRegistryRoot}\*" -Name InstallationFolder -ErrorAction Ignore `
                    | Select-Object -ExpandProperty InstallationFolder `
                    | Get-ChildItem -Recurse -Filter sn.exe -File `
                    | Sort-Object -Property @{Expression={$_.VersionInfo.ProductVersion -as [System.Version]}} -Descending `
                    | Select-Object -First 1 `
                    | Get-Command -Name {$_.FullName}
            }
        }
        if (-not $snExe) {
            throw 'File not found: sn.exe. The sn.exe executable is required when building management packs. It is included in the Windows SDK. Please download the latest version of the Windows SDK that is available for your version of Windows and then try again.'
        }

        # Find the SCSM Authoring Tool installation folder if we're building any workflows
        $scsmAuthoringToolInstallFolder = $null
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($path in @('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\System Center\2010\Service Manager Authoring Tool\Setup','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\System Center\2010\Service Manager Authoring Tool\Setup')) {
                if (Test-Path -LiteralPath $path) {
                    $scsmAuthoringToolInstallFolder = (Get-ItemProperty -LiteralPath $path -Name InstallDirectory | Select-Object -ExpandProperty InstallDirectory) -replace '\\$'
                    break
                }
            }
            if (-not $scsmAuthoringToolInstallFolder) {
                throw 'SCSM Authoring Tool not found. The SCSM Authoring Tool comes with several dlls that are required when building workflows. Please install the appropriate version of the SCSM Authoring Tool and try again.'
            }
        }

        # Identify default values for various management pack properties
        $name = $mpc.Name
        $company = ''
        $copyright = "Copyright $([System.DateTime]::Now.Year)"
        $displayName = $mpc.Name
        $description = ''
        $version = [System.Version]'1.0.0.0'

        # Now get the actual values according to the management pack configuration
        foreach ($mpcPropertyName in @('Company','Copyright','DisplayName','Description','Version')) {
            if (($mpc.Keys -contains 'Properties') -and
                ($mpc['Properties'].Keys -contains $mpcPropertyName)) {
                Set-Variable -Name $mpcPropertyName -Value $mpc['Properties'][$mpcPropertyName] -Confirm:$false -WhatIf:$false
            }
        }

        # Get the path to the project folder
        if (($mpc.Keys -contains 'BuildOptions') -and
            ($mpc['BuildOptions'].Keys -contains 'Location')) {
            $projectRoot = $mpc['BuildOptions']['Location']
        } else {
            $projectRoot = Join-Path -Path ([System.Environment]::GetFolderPath('MyDocuments')) -ChildPath $PSModule.Name
        }
        if ((Split-Path -Path $projectRoot -Leaf) -ne $mpc.Name) {
            $projectRoot = Join-Path -Path $projectRoot -ChildPath $mpc.Name
        }

        # If the project folder does not exist, create it
        if (-not (Test-Path -LiteralPath $projectRoot)) {
            New-Item -Path $projectRoot -ItemType Directory -Force > $null
        }
        if (-not (Test-Path -LiteralPath "${projectRoot}\mpb")) {
            New-Item -Path "${projectRoot}\mpb" -ItemType Directory -Force > $null
        }

        # Change the path to the project folder
        Push-Location -LiteralPath $projectRoot

        # Get the public key token from the strong-name key file
        $publicKeyToken = $null
        if (($mpc.Keys -contains 'BuildOptions') -and
            ($mpc['BuildOptions'].Keys -contains 'StrongNameKeyFile')) {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                & $snExe -q -p $mpc['BuildOptions']['StrongNameKeyFile'] $tempFile
                $publicKeyToken = $(& $snExe -q -t $tempFile) -replace '^\s+|\s+$' -split '\s+' | Select-Object -Last 1
            } finally {
                if (Test-Path -LiteralPath $tempFile) {
                    Remove-Item -LiteralPath $tempFile
                }
            }
        }

        # Get the code signing cert if one was provided
        $codeSigningCert = $null
        if (($mpc.Keys -contains 'BuildOptions') -and
            ($mpc['BuildOptions'].Keys -contains 'CodeSigningCertificate')) {
            $codeSigningCert = $mpc['BuildOptions']['CodeSigningCertificate']
        }

        # Get the icon for the management pack
        $icon = $null
        if (($mpc.Keys -contains 'BuildOptions') -and
            ($mpc['BuildOptions'].Keys -contains 'IconPath')) {
            $icon = $mpc['BuildOptions']['IconPath']
        }

        # Components/artifacts of a PowerShell inline script in SCSM
        # 1. MP xml
        #    a. Defines name, display name, version of MP.
        #    b. Optionally defines Administration Settings page with associated singleton class to configure the PowerShell inline script.
        #    c. Seal the MP using Protect-SCManagementPack.
        # 2. Administration Settings (Presentation) dll (optional)
        #    a. Compiled from .xaml file that defines the UI that is displayed for the optional administration settings.
        #    b. Sign the file (optionally) using a pfx cert.
        # 3. Workflow dll
        #    a. Compiled from .cs and .xoml files that define the workflow (a single activity that is used to invoke a PowerShell script).
        #    b. Sign the file (optionally) using a pfx cert.
        # Export these to disk, keep in .xml/.cs/.xoml/.xaml files, build the DLLs, then the MP, place all files in one location for packaging/installation.

        # Generate the management pack XML
        $managementPackXml = @"
<ManagementPack ContentReadable="true"
                SchemaVersion="2.0"
                OriginalSchemaVersion="1.1"
                xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <Manifest>
    <Identity>
      <ID>${name}</ID>
      <Version>${version}</Version>
    </Identity>
    <Name>${displayName}</Name>
    <References>
      <Reference Alias="System">
        <ID>System.Library</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="AdminItem">
        <ID>System.AdminItem.Library</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="SMUIConsole">
        <ID>Microsoft.EnterpriseManagement.ServiceManager.UI.Console</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="SMUIAdministration">
        <ID>Microsoft.EnterpriseManagement.ServiceManager.UI.Administration</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="SystemCenter">
        <ID>Microsoft.SystemCenter.Library</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="SystemCenterSubscriptions">
        <ID>Microsoft.SystemCenter.Subscriptions</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="Core">
        <ID>ServiceManager.Core.Library</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="Windows">
        <ID>Microsoft.Windows.Library</ID>
        <Version>7.0.5000.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
    </References>
  </Manifest>
  <TypeDefinitions>
    <EntityTypes>
      <ClassTypes>

"@
        if ($mpc.Keys -contains 'AdminSettings') {
            $managementPackXml += @"
        <ClassType ID="${name}.Settings"
                   Accessibility="Public"
                   Abstract="false"
                   Base="AdminItem!System.SolutionSettings"
                   Hosted="false"
                   Singleton="true">
$(foreach ($adminSettingsPageName in $mpc['AdminSettings'].Keys) {
    foreach ($adminSettingsPropertyName in $mpc['AdminSettings'][$adminSettingsPageName].Keys) {
        $adminSettingsProperty = $mpc['AdminSettings'][$adminSettingsPageName][$adminSettingsPropertyName]
        switch ($adminSettingsProperty.ProducedByKeyword -split '\\' | Select-Object -Last 1) {
            'BooleanProperty' {
                $propertyShortTypeName = 'bool'
                break
            }
            'IntegerProperty' {
                $propertyShortTypeName = 'int'
                break
            }
            'StringProperty' {
                $propertyShortTypeName = 'string'
                break
            }
        }
        $propertySettingXml = @"
          <Property ID="$($adminSettingsProperty.Name)"
                    Type="${propertyShortTypeName}"
"@
        if (($adminSettingsProperty.Keys -contains 'Mandatory') -and
            ($adminSettingsProperty['Mandatory'])) {
            $propertySettingXml += '
                    Required="true"'
        }
        if ($adminSettingsProperty.Keys -contains 'DefaultValue') {
            $defaultValue = $adminSettingsProperty['DefaultValue'].ToString()
            if ($adminSettingsProperty['DefaultValue'] -is [System.Boolean]) {
                $defaultValue = $defaultValue.ToLower()
            }
            $propertySettingXml += "
                    DefaultValue=""${defaultValue}"""
        }
        if ($adminSettingsProperty.Keys -contains 'HelpMessage') {
            $propertySettingXml += "
                    Comment=""$($adminSettingsProperty['HelpMessage'])"""
        }
        if (($adminSettingsProperty.Keys -contains 'MinValue') -and
            ($adminSettingsProperty.Keys -contains 'MaxValue')) {
                $propertySettingXml += "
                    MinValue=""$($adminSettingsProperty['MinValue'])""
                    MaxValue=""$($adminSettingsProperty['MaxValue'])"""
        }
        $propertySettingXml += @'
 />

'@
        $propertySettingXml
    }
})        </ClassType>

"@
        }
        $managementPackXml += @"
      </ClassTypes>
    </EntityTypes>
    <ModuleTypes>

"@
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($workflowName in $mpc['Workflows'].Keys) {
                $managementPackXml += @"
      <WriteActionModuleType ID="${name}.${workflowName}.WindowsPowerShellScript.MT"
                             Accessibility="Public"
                             RunAs="Core!Microsoft.SystemCenter.ServiceManager.WorkflowAccount"
                             Batching="false">
        <Configuration>
          <IncludeSchemaTypes>
            <SchemaType>Windows!Microsoft.Windows.PowerShellSchema</SchemaType>
          </IncludeSchemaTypes>
        </Configuration>
        <ModuleImplementation Isolation="Any">
          <Composite>
            <MemberModules>
              <WriteAction ID="${name}.${workflowName}.WindowsPowerShellScript.PSWA"
                           TypeID="Windows!Microsoft.Windows.PowerShellWriteAction">
                <ScriptName>${name}.${workflowName}.ps1</ScriptName>
                <ScriptBody>
$($mpc['Workflows'][$workflowName]['ScriptBlock'])</ScriptBody>
                <SnapIns></SnapIns>
                <Parameters></Parameters>
                <TimeoutSeconds>300</TimeoutSeconds>
                <StrictErrorHandling>true</StrictErrorHandling>
                <SerializationDepth>3</SerializationDepth>
              </WriteAction>
            </MemberModules>
            <Composition>
              <Node ID="${name}.${workflowName}.WindowsPowerShellScript.PSWA" />
            </Composition>
          </Composite>
        </ModuleImplementation>
        <InputType>System!System.BaseData</InputType>
      </WriteActionModuleType>

"@
            }
        }
        $managementPackXml += @'
    </ModuleTypes>
  </TypeDefinitions>
  <Categories>

'@
        if ($mpc.Keys -contains 'AdminSettings') {
            $managementPackXml += @"
    <Category ID="Category.DoubleClickEditAdminSetting"
              Target="${name}.Settings.Edit"
              Value="SMUIConsole!Microsoft.EnterpriseManagement.ServiceManager.UI.Console.DoubleClickTask" />

"@
        }
        $managementPackXml += @"
    <Category ID="SCSMMPCategory"
              Value="SMUIConsole!Microsoft.EnterpriseManagement.ServiceManager.ManagementPack">
      <ManagementPackName>${name}</ManagementPackName>
      <ManagementPackVersion>${version}</ManagementPackVersion>

"@
        if ($publicKeyToken) {
            $managementPackXml += @"
      <ManagementPackPublicKeyToken>${publicKeyToken}</ManagementPackPublicKeyToken>

"@
        }
        $managementPackXml += @"
    </Category>

"@
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($workflowName in $mpc['Workflows'].Keys) {
                $managementPackXml += @"
    <Category ID="${name}.${workflowName}.Category"
              Target="${name}.${workflowName}.Workflow"
              Value="SMUIAdministration!Microsoft.EnterpriseManagement.ServiceManager.Rules.WorkflowSubscriptions" />

"@
            }
        }
        $managementPackXml += @'
  </Categories>
  <Monitoring>
    <Rules>

'@
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($workflowName in $mpc['Workflows'].Keys) {
                $managementPackXml += @"
      <Rule ID="${name}.${workflowName}.Workflow"
            Enabled="true"
            Target="SystemCenter!Microsoft.SystemCenter.SubscriptionWorkflowTarget"
            ConfirmDelivery="false"
            Remotable="true"
            Priority="Normal"
            DiscardLevel="100">
        <Category>Notification</Category>
        <DataSources>

"@
                $trigger = $mpc['Triggers'][$mpc['Workflows'][$workflowName]['TriggerName']]
                switch ($trigger.ProducedByKeyword -split '\\' | Select-Object -Last 1) {
                    'DailySchedule' {
                        $managementPackXml += @"
          <DataSource ID="SchedulerDS"
                      RunAs="SystemCenter!Microsoft.SystemCenter.DatabaseWriteActionAccount"
                      TypeID="System!System.Scheduler">
            <Scheduler>
              <WeeklySchedule>
                <Windows>
                  <Daily>
                    <Start>$($trigger['StartTime'])</Start>
                    <End>00:00</End>
                    <DaysOfWeekMask>$($trigger['DaysOfWeekMask'])</DaysOfWeekMask>
                  </Daily>
                </Windows>
              </WeeklySchedule>
              <ExcludeDates />
            </Scheduler>
          </DataSource>

"@
                        break
                    }
                    default {
                        # Not supported yet
                    }
                }
                $managementPackXml += @"
        </DataSources>
        <WriteActions>
          <WriteAction ID="WA"
                       TypeID="SystemCenterSubscriptions!Microsoft.EnterpriseManagement.SystemCenter.Subscription.WindowsWorkflowTaskWriteAction">
            <Subscription>
              <WindowsWorkflowConfiguration>
                <AssemblyName>${name}.${workflowName}</AssemblyName>
                <WorkflowTypeName>WorkflowAuthoring.$($workflowName -replace '[\W_]')Activity</WorkflowTypeName>
                <WorkflowParameters></WorkflowParameters>
                <RetryExceptions></RetryExceptions>
                <RetryDelaySeconds>60</RetryDelaySeconds>
                <MaximumRunningTimeSeconds>300</MaximumRunningTimeSeconds>
              </WindowsWorkflowConfiguration>
            </Subscription>
          </WriteAction>
        </WriteActions>
      </Rule>

"@
            }
        }
        $managementPackXml += @'
    </Rules>
    <Tasks>

'@
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($workflowName in $mpc['Workflows'].Keys) {
                $managementPackXml += @"
      <Task ID="${name}.${workflowName}Task"
            Accessibility="Public"
            Enabled="true"
            Target="Windows!Microsoft.Windows.Computer"
            Timeout="300"
            Remotable="true">
        <Category>Notification</Category>
        <WriteAction ID="${name}.${workflowName}.WindowsPowerShellScript.WA"
                     TypeID="${name}.${workflowName}.WindowsPowerShellScript.MT" />
      </Task>

"@
            }
        }
        $managementPackXml += @'
    </Tasks>
  </Monitoring>

'@
        if ($mpc.Keys -contains 'AdminSettings') {
            $managementPackXml += @"
  <Presentation>
    <ConsoleTasks>
      <!-- Task to open a form to manage Settings class values -->
      <ConsoleTask ID="${name}.Settings.Edit"
                   Accessibility="Public"
                   Enabled="true"
                   Target="${name}.Settings"
                   RequireOutput="false">
        <Assembly>SMUIConsole!SdkDataAccessAssembly</Assembly>
        <Handler>Microsoft.EnterpriseManagement.UI.SdkDataAccess.ConsoleTaskHandler</Handler>
        <Parameters>
          <Argument Name="Assembly">${name}.Settings</Argument>
          <Argument Name="Type">${name}.SettingsConsoleCommand</Argument>
        </Parameters>
      </ConsoleTask>
    </ConsoleTasks>
    <ImageReferences>
      <ImageReference ElementID="${name}.Settings" ImageID="$(if ($icon) {"${name}.Settings.Icon"} else {'SMUIAdministration!Microsoft.EnterpriseManagement.ServiceManager.UI.Administration.Image.Settings'})" />
      <ImageReference ElementID="${name}.Settings.Edit" ImageID="SMUIConsole!Microsoft.EnterpriseManagement.ServiceManager.UI.Console.Image.Properties" />
    </ImageReferences>
  </Presentation>

"@
        }
        $managementPackXml += @"
  <LanguagePacks>
    <LanguagePack ID="ENU" IsDefault="true">
      <DisplayStrings>
        <!-- Management Pack display name and description -->
        <DisplayString ElementID="${name}">
          <Name>${displayName}</Name>
          <Description>${description}</Description>
        </DisplayString>

"@
        if ($mpc.Keys -contains 'AdminSettings') {
            $managementPackXml += @"
        <!-- Settings class display name and description-->
        <DisplayString ElementID="${name}.Settings">
          <Name>${displayName} Settings</Name>
          <Description>Settings for the ${displayName} workflows.</Description>
        </DisplayString>
        <!-- Edit task display name and description -->
        <DisplayString ElementID="${name}.Settings.Edit">
          <Name>Properties</Name>
          <Description>View or configure settings for the ${displayName} workflows.</Description>
        </DisplayString>

"@
        }
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($workflowName in $mpc['Workflows'].Keys) {
                $managementPackXml += @"
        <!-- Edit workflow display name and description -->
        <DisplayString ElementID="${name}.${workflowName}.Workflow">
          <Name>$(if ($mpc['Workflows'][$workflowName].Keys -contains 'DisplayName') {$mpc['Workflows'][$workflowName]['DisplayName']} else {$displayName})</Name>
          <Description>$(if ($mpc['Workflows'][$workflowName].Keys -contains 'Description') {$mpc['Workflows'][$workflowName]['Description']} else {$description})</Description>
        </DisplayString>

"@
            }
        }
        $managementPackXml += @'
      </DisplayStrings>
    </LanguagePack>
  </LanguagePacks>
  <Resources>

'@
        if ($mpc.Keys -contains 'AdminSettings') {
            $managementPackXml += @"
    <Assembly ID="${Name}.Settings.Assembly" Accessibility="Public" FileName="${Name}.Settings.dll" QualifiedName="${Name}.Settings" />

"@
            if ($icon) {
                $managementPackXml += @"
    <Image ID="${Name}.Settings.Icon" Accessibility="Public" FileName="$(Split-Path -Path $icon -Leaf)" />

"@
            }
        }
        $managementPackXml += @'
  </Resources>
</ManagementPack>
'@

        $filePath = Join-Path -Path $projectRoot -ChildPath "mpb\${name}.xml"
        [System.IO.File]::WriteAllText($filePath,$managementPackXml,[System.Text.Encoding]::UTF8)

        # Generate the settings DLL files
        if ($mpc.Keys -contains 'AdminSettings') {
            # Generate the settings AssemblyInfo.cs file
            $assemblyInfoCs = @"
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

// General Information about an assembly is controlled through the following 
// set of attributes. Change these attribute values to modify the information
// associated with an assembly.
[assembly: AssemblyTitle("${name}.Presentation")]
[assembly: AssemblyDescription("")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("${company}")]
[assembly: AssemblyProduct("${name}")]
[assembly: AssemblyCopyright("${copyright}")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]

// Setting ComVisible to false makes the types in this assembly not visible 
// to COM components.  If you need to access a type in this assembly from 
// COM, set the ComVisible attribute to true on that type.
[assembly: ComVisible(false)]

// The following GUID is for the ID of the typelib if this project is exposed to COM
[assembly: Guid("$([System.Guid]::NewGuid())")]

// Version information for an assembly consists of the following four values:
//
//      Major Version
//      Minor Version 
//      Build Number
//      Revision
//
// You can specify all the values or you can default the Build and Revision Numbers 
// by using the '*' as shown below:
// [assembly: AssemblyVersion("1.0.*")]
[assembly: AssemblyVersion("${version}")]
[assembly: AssemblyFileVersion("${version}")]
"@

            $filePath = Join-Path -Path $projectRoot -ChildPath "mpb\AssemblyInfo.cs"
            [System.IO.File]::WriteAllText($filePath,$assemblyInfoCs,[System.Text.Encoding]::UTF8)

            foreach ($adminSettingsPageName in $mpc['AdminSettings'].Keys) {
                # Generate the settings *SettingsPage.xaml file
                $settingsPageXaml = @"
<wpfwiz:WizardRegularPageBase x:Class="${name}.${adminSettingsPageName}SettingsPage"
                              xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                              xmlns:local="clr-namespace:${name}"
                              xmlns:wpfwiz="clr-namespace:Microsoft.EnterpriseManagement.UI.WpfWizardFramework;assembly=Microsoft.EnterpriseManagement.UI.WpfWizardFramework" Loaded="WizardRegularPageBase_Loaded">
  <ScrollViewer Margin="0,0,0,0" Name="scrollViewer" CanContentScroll="True" VerticalScrollBarVisibility="Auto">
    <Grid Margin="15,15,15,15">
      <Grid.RowDefinitions>
$(
foreach ($adminSettingsPropertyName in $mpc['AdminSettings'][$adminSettingsPageName].Keys) {
    "        <RowDefinition Height=""Auto"" />`r`n"
}
)
      </Grid.RowDefinitions>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*" />
        <ColumnDefinition Width="100" />
      </Grid.ColumnDefinitions>
      <Grid.Resources>
        <Style TargetType="{x:Type Label}">
          <Setter Property="Margin" Value="4,4,4,4" />
          <Setter Property="VerticalAlignment" Value="Center" />
          <Setter Property="Grid.Column" Value="0" />
        </Style>
        <Style TargetType="{x:Type TextBox}">
          <Setter Property="Margin" Value="4,4,4,4" />
          <Setter Property="VerticalAlignment" Value="Center" />
          <Setter Property="TextAlignment" Value="Right" />
          <Setter Property="Grid.Column" Value="1" />
        </Style>
        <Style TargetType="{x:Type CheckBox}">
          <Setter Property="Margin" Value="4,4,4,4" />
          <Setter Property="VerticalAlignment" Value="Center" />
          <Setter Property="HorizontalAlignment" Value="Center" />
          <Setter Property="Grid.Column" Value="1" />
        </Style>
        <Style TargetType="{x:Type Binding}">
          <Setter Property="Mode" Value="TwoWay" />
          <Setter Property="FallbackValue" Value="" />
        </Style>
      </Grid.Resources>
$(
$index = 0
foreach ($adminSettingsPropertyName in $mpc['AdminSettings'][$adminSettingsPageName].Keys) {
    $adminSettingsProperty = $mpc['AdminSettings'][$adminSettingsPageName][$adminSettingsPropertyName]
    @"
      <Label Content="$($adminSettingsProperty['Label'])" Grid.Row="${index}"/>

"@
    switch ($adminSettingsProperty.ProducedByKeyword -split '\\' | Select-Object -Last 1) {
        'BooleanProperty' {
            @"
      <CheckBox Grid.Row="${index}">
        <CheckBox.IsChecked>
          <Binding Path="$($adminSettingsProperty.Name)" />
        </CheckBox.IsChecked>
      </CheckBox>

"@
            break
        }
        default {
            @"
      <TextBox Grid.Row="${index}">
        <TextBox.Text>
          <Binding Path="$($adminSettingsProperty.Name)" />
        </TextBox.Text>
      </TextBox>

"@
            break
        }
    }
    $index++
}
)    </Grid>
  </ScrollViewer>
</wpfwiz:WizardRegularPageBase>
"@

                $filePath = Join-Path -Path $projectRoot -ChildPath "mpb\${adminSettingsPageName}SettingsPage.xaml"
                [System.IO.File]::WriteAllText($filePath,$settingsPageXaml,[System.Text.Encoding]::UTF8)

                # Generate the settings *SettingsPage.xaml.cs file
                $settingsPageXamlCs = @"
using System;
using System.Windows;
using Microsoft.EnterpriseManagement.UI.WpfWizardFramework;

namespace ${name}
{
    public partial class ${adminSettingsPageName}SettingsPage : WizardRegularPageBase
    {
        private Settings settings = null;

        public ${adminSettingsPageName}SettingsPage(WizardData wizardData)
        {
            InitializeComponent();

            this.DataContext = wizardData;
            this.settings = this.DataContext as Settings;
        }

        private void WizardRegularPageBase_Loaded(object sender, RoutedEventArgs e)
        {
        }
    }
}
"@

                $filePath = Join-Path -Path $projectRoot -ChildPath "mpb\${adminSettingsPageName}SettingsPage.xaml.cs"
                [System.IO.File]::WriteAllText($filePath,$settingsPageXamlCs,[System.Text.Encoding]::UTF8)
            }

            # Generate the settings SettingsConsoleCommand.cs file
            $settingsConsoleCommandCs = @"
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Win32;
using Microsoft.EnterpriseManagement;
using Microsoft.EnterpriseManagement.Common;
using Microsoft.EnterpriseManagement.Configuration;
using Microsoft.EnterpriseManagement.UI.WpfWizardFramework;
using Microsoft.EnterpriseManagement.UI.SdkDataAccess;
using Microsoft.EnterpriseManagement.ConsoleFramework;

namespace ${name}
{
    public class SettingsConsoleCommand : ConsoleCommand
    {
        public SettingsConsoleCommand()
        {
        }

        public override void ExecuteCommand(IList<NavigationModelNodeBase> nodes, NavigationModelNodeTask task, ICollection<string> parameters)
        {
            //Get the server name to connect to and connect to the server
            String strServerName = Registry.GetValue("HKEY_CURRENT_USER\\Software\\Microsoft\\System Center\\2010\\Service Manager\\Console\\User Settings", "SDKServiceMachine", "localhost").ToString();
            EnterpriseManagementGroup emg = new EnterpriseManagementGroup(strServerName);

            // Get the management pack so that we can look up the singleton Settings object
            ManagementPack mp = emg.ManagementPacks.GetManagementPack("${name}","${publicKeyToken}",new Version("${version}"));

            // Get the singleton Settings class
            ManagementPackClass mpClass = mp.GetClass("${name}.Settings");

            // Now process the one and only instance of the singleton Settings class
            foreach (EnterpriseManagementObject emoData in emg.EntityObjects.GetObjectReader<EnterpriseManagementObject>(mpClass, ObjectQueryOptions.Default))
            {
                //Create a new "wizard", set the title bar, create the data, and add the pages
                WizardStory wizard = new WizardStory();
                wizard.WizardWindowTitle = "Edit ${displayName} Settings";
                WizardData data = new Settings(emoData);
                wizard.WizardData = data;
$(
foreach ($adminSettingsPageName in $mpc['AdminSettings'].Keys) {
    "                wizard.AddLast(new WizardStep(""${adminSettingsPageName}"", typeof(${adminSettingsPageName}SettingsPage), wizard.WizardData));
"
})
                //Show the property page
                PropertySheetDialog wizardWindow = new PropertySheetDialog(wizard);

                //Update the view when done so the new values are shown
                bool? dialogResult = wizardWindow.ShowDialog();
                if (dialogResult.HasValue && dialogResult.Value)
                {
                    RequestViewRefresh();
                }
                break;
            }
        }
    }
}
"@

            $filePath = Join-Path -Path $projectRoot -ChildPath "mpb\SettingsConsoleCommand.cs"
            [System.IO.File]::WriteAllText($filePath,$settingsConsoleCommandCs,[System.Text.Encoding]::UTF8)

            # Generate the settings Settings.cs file
            $settingsCs = @"
using System;
using Microsoft.EnterpriseManagement;
using Microsoft.EnterpriseManagement.Common;
using Microsoft.EnterpriseManagement.Configuration;
using Microsoft.EnterpriseManagement.UI.WpfWizardFramework;

namespace ${name}
{
    class Settings : WizardData
    {
        #region Variables

        private ManagementPackClass mpClass;
        private EnterpriseManagementObject emoData = null;

$(
foreach ($adminSettingsPageName in $mpc['AdminSettings'].Keys) {
    foreach ($adminSettingsPropertyName in $mpc['AdminSettings'][$adminSettingsPageName].Keys) {
        $adminSettingsProperty = $mpc['AdminSettings'][$adminSettingsPageName][$adminSettingsPropertyName]
        switch ($adminSettingsProperty.ProducedByKeyword -split '\\' | Select -Last 1) {
            'IntegerProperty' {
                @"
        public string ${adminSettingsPropertyName}
        {
            get
            {
                return Convert.ToString((int)emoData[mpClass, "${adminSettingsPropertyName}"].Value);
            }
            set
            {
                int newValue;
                if ((Convert.ToString((int)emoData[mpClass, "${adminSettingsPropertyName}"].Value) != value) &&
                    Int32.TryParse(value, out newValue))
                {
                    emoData[mpClass, "${adminSettingsPropertyName}"].Value = newValue;
                }
            }
        }


"@
                break
            }
            'BooleanProperty' {
                @"
        public bool ${adminSettingsPropertyName}
        {
            get
            {
                return (bool)emoData[mpClass, "${adminSettingsPropertyName}"].Value;
            }
            set
            {
                emoData[mpClass, "${adminSettingsPropertyName}"].Value = value;
            }
        }


"@
                break
            }
            'StringProperty' {
                @"
        public string ${adminSettingsPropertyName}
        {
            get
            {
                return (string)emoData[mpClass, "${adminSettingsPropertyName}"].Value;
            }
            set
            {
                emoData[mpClass, "${adminSettingsPropertyName}"].Value = value;
            }
        }


"@
                break
            }
        }
    }
}
)

        #endregion

        internal Settings(EnterpriseManagementObject emoData)
        {
            //Get the management group from the Enterprise Management Object
            EnterpriseManagementGroup emg = emoData.ManagementGroup;

            // Get the management pack so that we can look up property values
            ManagementPack mp = emg.ManagementPacks.GetManagementPack("${name}","${publicKeyToken}",new Version("${version}"));

            // Store the singleton Settings class
            this.mpClass = mp.GetClass("${name}.Settings");

            // Store the Emo Data object
            this.emoData = emoData;
        }

        public override void AcceptChanges(WizardMode wizardMode)
        {
            // Push the new configuration data into SCSM
            this.emoData.Commit();

            this.WizardResult = WizardResult.Success;
        }
    }
}
"@

            $filePath = Join-Path -Path $projectRoot -ChildPath "mpb\Settings.cs"
            [System.IO.File]::WriteAllText($filePath,$settingsCs,[System.Text.Encoding]::UTF8)

            # Generate the settings project file (Settings.proj)
            $SettingsProj = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <AssemblyName>${name}.Settings</AssemblyName>
    <OutputType>library</OutputType>
    <Configuration>Release</Configuration>
    <Platform>AnyCPU</Platform>
    <OutputPath>bin\Release\</OutputPath>
    <CopyLocal>false</CopyLocal>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="System" />
    <Reference Include="System.Core" />
    <Reference Include="System.Xml" />
    <Reference Include="WindowsBase" />
    <Reference Include="PresentationCore" />
    <Reference Include="PresentationFramework" />
    <Reference Include="Microsoft.EnterpriseManagement.UI.WpfWizardFramework">
      <HintPath>${scsmInstallFolder}\Microsoft.EnterpriseManagement.UI.WpfWizardFramework.dll</HintPath>
    </Reference>
    <Reference Include="Microsoft.EnterpriseManagement.UI.SdkDataAccess">
      <HintPath>${scsmInstallFolder}\Microsoft.EnterpriseManagement.UI.SdkDataAccess.dll</HintPath>
    </Reference>
    <Reference Include="Microsoft.EnterpriseManagement.UI.Foundation">
      <HintPath>${scsmInstallFolder}\Microsoft.EnterpriseManagement.UI.Foundation.dll</HintPath>
    </Reference>
    <Reference Include="Microsoft.EnterpriseManagement.Core">
      <HintPath>${scsmInstallFolder}\SDK Binaries\Microsoft.EnterpriseManagement.Core.dll</HintPath>
    </Reference>
  </ItemGroup>
  <ItemGroup>
    <Compile Include="AssemblyInfo.cs" />

"@
            foreach ($adminSettingsPageName in $mpc['AdminSettings'].Keys) {
                $SettingsProj += @"
    <Page Include="${adminSettingsPageName}SettingsPage.xaml" />
    <Compile Include="${adminSettingsPageName}SettingsPage.xaml.cs" />

"@
            }
            $SettingsProj += @'
    <Compile Include="SettingsConsoleCommand.cs" />
    <Compile Include="Settings.cs" />
  </ItemGroup>
  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
  <Import Project="$(MSBuildBinPath)\Microsoft.WinFX.targets" />
</Project>
'@

            $filePath = Join-Path -Path $projectRoot -ChildPath "mpb\Settings.proj"
            [System.IO.File]::WriteAllText($filePath,$settingsProj,[System.Text.Encoding]::UTF8)
        }

        # Generate the workflow DLL files
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($workflowName in $mpc['Workflows'].Keys) {
                # Create the folder to store the workflow files
                if (-not (Test-Path -LiteralPath "${projectRoot}\workflow\${workflowName}")) {
                    New-Item -Path "${projectRoot}\workflow\${workflowName}" -ItemType Directory -Force > $null
                }

                # Identify the script block that the workflow will use
                $scriptBlock = $null
                switch ($mpc['Workflows'][$workflowName].ProducedByKeyword -split '\\' | Select-Object -Last 1) {
                    'PowerShellScript' {
                        $scriptBlock = $mpc['Workflows'][$workflowName]['ScriptBlock']
                        break
                    }
                    'PowerShellScriptFile' {
                        $scriptBlock = $ExecutionContext.InvokeCommand.NewScriptBlock((Get-Content -LiteralPath $mpc['Workflows'][$workflowName]['Path'] -Raw))
                        break
                    }
                    'SmaRunbook' {
                        $scriptBlock = $ExecutionContext.InvokeCommand.NewScriptBlock("Start-SmaRunbook -WebServiceEndpoint $($mpc['Workflows'][$workflowName]['Endpoint']) -Name $($mpc['Workflows'][$workflowName]['RunbookName'])")
                        break
                    }
                }
                
                # Generate the AssemblyInfo.cs file
                $assemblyInfoCs = @"
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

// General Information about an assembly is controlled through the following 
// set of attributes. Change these attribute values to modify the information
// associated with an assembly.
[assembly: AssemblyTitle("${name}.${workflowName}Workflow")]
[assembly: AssemblyDescription("")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("${company}")]
[assembly: AssemblyProduct("${name}")]
[assembly: AssemblyCopyright("${copyright}")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]

// Setting ComVisible to false makes the types in this assembly not visible 
// to COM components.  If you need to access a type in this assembly from 
// COM, set the ComVisible attribute to true on that type.
[assembly: ComVisible(false)]

// The following GUID is for the ID of the typelib if this project is exposed to COM
[assembly: Guid("$([System.Guid]::NewGuid())")]

// Version information for an assembly consists of the following four values:
//
//      Major Version
//      Minor Version 
//      Build Number
//      Revision
//
// You can specify all the values or you can default the Build and Revision Numbers 
// by using the '*' as shown below:
// [assembly: AssemblyVersion("1.0.*")]
[assembly: AssemblyVersion("${version}")]
[assembly: AssemblyFileVersion("${version}")]
"@

                $filePath = Join-Path -Path $projectRoot -ChildPath "workflow\${workflowName}\AssemblyInfo.cs"
                [System.IO.File]::WriteAllText($filePath,$assemblyInfoCs,[System.Text.Encoding]::UTF8)

                # Generate the Workflow.xoml file
                $workflowXoml = @"
<SequentialWorkflowActivity x:Class="WorkflowAuthoring.$($workflowName -replace '[\W_]')Activity"
                            x:Name="$($workflowName -replace '[\W_]')"
                            xmlns:ns0="clr-namespace:Microsoft.ServiceManager.WorkflowAuthoring.ActivityLibrary;Assembly=Microsoft.ServiceManager.WorkflowAuthoring.ActivityLibrary, Version=7.0.5000.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
                            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                            xmlns="http://schemas.microsoft.com/winfx/2006/xaml/workflow">
  <ns0:WindowsPowerShellScript Parameter="{x:Null}"
                               SnapIns="{x:Null}"
                               x:Name="windowsPowerShellScriptActivity"
                               PropertyToBind="{x:Null}"
                               ScriptBody="$($scriptBlock.ToString() -replace '&','&amp;' -replace '"','&quot;' -replace '<','&lt;' -replace '>','&gt;' -replace '''','&apos;' -replace "`r`n|`r|`n",'&#xD;&#xA;')"
                               TaskID="${name}.${workflowName}Task"
                               ScriptName="{x:Null}">
    <ns0:WindowsPowerShellScript.Parameters>
      <x:Array Type="{x:Type p7:ActivityParameter}"
               xmlns:p7="clr-namespace:Microsoft.ServiceManager.WorkflowAuthoring.Common;Assembly=Microsoft.ServiceManager.WorkflowAuthoring.Common, Version=7.0.5000.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" />
    </ns0:WindowsPowerShellScript.Parameters>
  </ns0:WindowsPowerShellScript>
</SequentialWorkflowActivity>
"@

                $filePath = Join-Path -Path $projectRoot -ChildPath "workflow\${workflowName}\Workflow.xoml"
                [System.IO.File]::WriteAllText($filePath,$workflowXoml,[System.Text.Encoding]::UTF8)

                # Generate the Workflow.cs file
                $workflowCs = @"
//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by a tool.
//     Runtime Version:2.0.50727.8000
//
//     Changes to this file may cause incorrect behavior and will be lost if
//     the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

namespace WorkflowAuthoring
{
    using System;
    using System.ComponentModel;
    using System.ComponentModel.Design;
    using System.Workflow.ComponentModel.Design;
    using System.Workflow.ComponentModel;
    using System.Workflow.ComponentModel.Serialization;
    using System.Workflow.ComponentModel.Compiler;
    using System.Drawing;
    using System.Collections;
    using System.Workflow.Activities;
    using System.Workflow.Runtime;
    
    
    public partial class $($workflowName -replace '[\W_]')Activity : System.Workflow.Activities.SequentialWorkflowActivity
    {
    }
}
"@

                $filePath = Join-Path -Path $projectRoot -ChildPath "workflow\${workflowName}\Workflow.cs"
                [System.IO.File]::WriteAllText($filePath,$workflowCs,[System.Text.Encoding]::UTF8)
            }
        }

        # Build the Settings dll file and sign it if we have a cert
        $settingsDll = $null
        if ($mpc.Keys -contains 'AdminSettings') {
            $msBuildResults = & "${env:windir}\Microsoft.NET\Framework\v3.5\MSBuild.exe" "${projectRoot}\mpb\Settings.proj"
            if ($msBuildResults -join "`r`n" -notmatch 'Build succeeded\.') {
                throw "Management pack compile failed.`r`n$($msBuildResults -join "`r`n")"
            }
            $settingsDll = Get-Item -LiteralPath "${projectRoot}\mpb\bin\Release\$($mpc.Name).Settings.dll"
            if ($codeSigningCert) {
                Set-AuthenticodeSignature -Certificate $codeSigningCert -TimestampServer http://timestamp.verisign.com/scripts/timstamp.dll -FilePath $settingsDll.FullName > $null
            }
            $settingsDll = Move-Item -LiteralPath $settingsDll.FullName -Destination "${projectRoot}\mpb" -Force -PassThru
            # Remove the obj and bin folders
            Remove-Item -LiteralPath "${projectRoot}\mpb\obj" -Recurse -Force
            Remove-Item -LiteralPath "${projectRoot}\mpb\bin" -Recurse -Force
        }

        # Seal the MP if we were able to get a public key token from an SNK file earlier
        $sealedMpFile = $null
        if ($publicKeyToken) {
            Protect-SCManagementPack -ManagementPackFile "mpb\$($mpc.Name).xml" -KeyFilePath $mpc['BuildOptions']['StrongNameKeyFile'] -CompanyName $company -Copyright $copyright -OutputDirectory "${projectRoot}\mpb"
            $sealedMpFile = Get-Item -LiteralPath "${projectRoot}\mpb\$($mpc.Name).mp"
        }

        # Create the Management Pack bundle if we have a sealed MP file and a settings or icon file to bundle with it
        if ($sealedMpFile -and ($settingsDll -or $icon)) {
            Copy-Item -LiteralPath $icon -Destination "${projectRoot}\mpb" -Force
            if (-not (Test-Path -LiteralPath "${projectRoot}\release")) {
                New-Item -Path "${projectRoot}\release" -ItemType Directory -Force > $null
            }
            $managementPackBundle = New-ScsmPxManagementPackBundle -Path "${projectRoot}\release\$($mpc.Name).mpb" -InputObject $sealedMpFile.FullName
            # Remove the settings DLL (it was compiled into the MPB)
            Remove-Item -LiteralPath $settingsDll.FullName -Force
            # Remove the sealed MP file and the resources file that are generated
            Remove-Item -LiteralPath $sealedMpFile.FullName -Force
        }
    
        # Compile each of the workflow DLLs (use a background job so that resources are released when the job finishes).
        if ($mpc.Keys -contains 'Workflows') {
            foreach ($workflowName in $mpc['Workflows'].Keys) {
                $workflowDll = Start-Job -ScriptBlock {
                    # TODO: switch from args to parameters later
                    if (-not (Test-Path -LiteralPath $args[2])) {
                        New-Item -Path $args[2] -ItemType Directory -Force > $null
                    }

                    $assemblyPath = Join-Path -Path $args[2] -ChildPath "$($args[0]).dll"

                    $scsmInstallFolder = Get-ScsmPxInstallDirectory

                    $scsmAuthoringToolInstallFolder = $null
                    foreach ($path in @('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\System Center\2010\Service Manager Authoring Tool\Setup','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\System Center\2010\Service Manager Authoring Tool\Setup')) {
                        if (Test-Path -LiteralPath $path) {
                            $scsmAuthoringToolInstallFolder = (Get-ItemProperty -LiteralPath $path -Name InstallDirectory | Select-Object -ExpandProperty InstallDirectory) -replace '\\$'
                            break
                        }
                    }

                    if (Test-Path -LiteralPath $assemblyPath) {
                        Remove-Item -LiteralPath $assemblyPath -Force -ErrorAction Stop
                    }

                    Add-Type -AssemblyName System.Workflow.ComponentModel

                    $wfCompiler = New-Object -TypeName System.Workflow.ComponentModel.Compiler.WorkflowCompiler
                    $wfCompilerParameters = New-Object -TypeName System.Workflow.ComponentModel.Compiler.WorkflowCompilerParameters
                    $wfCompilerParameters.ReferencedAssemblies.Add("${scsmAuthoringToolInstallFolder}\PackagesToLoad\Microsoft.ServiceManager.WorkflowAuthoring.ActivityLibrary.dll") > $null
                    $wfCompilerParameters.ReferencedAssemblies.Add("${scsmAuthoringToolInstallFolder}\PackagesToLoad\Microsoft.ServiceManager.WorkflowAuthoring.Common.dll") > $null
                    $wfCompilerParameters.OutputAssembly = $assemblyPath
                    $wfCompilerParameters.LibraryPaths.Add($scsmInstallFolder) > $null
                    $results = $wfCompiler.Compile(
                        $wfCompilerParameters,
                        [string[]]@(
                            "$($args[1])\AssemblyInfo.cs"
                            "$($args[1])\Workflow.xoml"
                            "$($args[1])\Workflow.cs"
                        )
                    )
                    if ($results.Errors.Count -gt 0) {
                        throw "Workflow compile failed. There were $($results.Errors.Count) errors.`r`n$($results.Errors -join "`r`n")"
                    }
                    Get-Item -LiteralPath $assemblyPath
                } -ArgumentList "$($mpc.Name).${workflowName}","${projectRoot}\workflow\${workflowName}","${projectRoot}\release" | Wait-Job | Receive-Job

                if ($codeSigningCert) {
                    Set-AuthenticodeSignature -Certificate $codeSigningCert -TimestampServer http://timestamp.verisign.com/scripts/timstamp.dll -FilePath $workflowDll.FullName > $null
                }
            }
        }
    } catch {
        throw
    } finally {
        Pop-Location
    }
}

#endregion

#region Clean-up the module when it is removed.

$PSModule.OnRemove = {
    #region Remove the domain-specific language from the session, releasing any keywords and aliases that it defined in the process.

    Remove-DomainSpecificLanguage -Name $PSModule.Name

    #endregion
}

#endregion