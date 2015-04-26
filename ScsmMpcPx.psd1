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

@{
      ModuleToProcess = 'ScsmMpcPx.psm1'

        ModuleVersion = '0.9.0.1'

                 GUID = '351fa979-6dfe-41a7-8e47-3b181fd74dd6'

               Author = 'Kirk Munro'

          CompanyName = 'Poshoholic Studios'

            Copyright = 'Copyright 2015 Provance Technologies'

          Description = 'DESCRIPTION'

    PowerShellVersion = '4.0'
    
        NestedModules = @(
                        'SnippetPx'
                        'LanguagePx'
                        )

      RequiredModules = @(
                        'ScsmPx'
                        )

      AliasesToExport = @(
                        'ManagementPackConfiguration'
                        )

             FileList = @(
                        'ScsmMpcPx.psd1'
                        'ScsmMpcPx.psm1'
                        'LICENSE'
                        'NOTICE'
                        'en-us\about_ScsmMpcPx.xml'
                        )

          PrivateData = @{
                            PSData = @{
                                Tags = 'dsl domain specific modeling language system center service manager scsm management pack'
                                LicenseUri = 'http://apache.org/licenses/LICENSE-2.0.txt'
                                ProjectUri = 'https://github.com/KirkMunro/ScsmMpcPx'
                                IconUri = ''
                                ReleaseNotes = ''
                            }
                        }
}