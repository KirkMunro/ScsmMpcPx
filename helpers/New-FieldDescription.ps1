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

function New-FieldDescription {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Host.FieldDescription])]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter(Position=1, Mandatory=$true)]
        [ValidateNotNull()]
        [System.Type]
        $Type,

        [Parameter(Position=2, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Label,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSObject]
        $DefaultValue,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $HelpMessage,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.Attribute[]]
        $Attributes,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Mandatory
    )
    try {
        $fieldDescription = New-Object -TypeName System.Management.Automation.Host.FieldDescription -ArgumentList $Name
        $fieldDescription.SetParameterType($Type)
        $fieldDescription.Label = $Label
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('DefaultValue')) {
            $fieldDescription.DefaultValue = $DefaultValue -as $Type
        }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('HelpMessage')) {
            $fieldDescription.HelpMessage = $HelpMessage
        }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Attributes')) {
            foreach ($attribute in $Attributes) {
                $fieldDescription.Attributes.Add($attribute)
            }
        }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Mandatory') -and $Mandatory) {
            $fieldDescription.IsMandatory = $true
        }
        $fieldDescription
    } catch {
        throw
    }
}