## ScsmMpcPx

### Overview

The ScsmMpcPx module defines a domain-specific language that simplifies the
creation of SCSM Management Packs. The intent of this DSL is to make it much
easier for IT administrators to create simple SCSM Management Packs that
contain a small number of features (one or more workflows that can be run in
Windows PowerShell, an administrative settings property page, schedules for
the workflows, and some class definitions). This method of management pack
creation does not require Visual Studio, nor does it require use of the
SCSM Authoring tool. All work is done in the management pack definition.

### Minimum requirements

- PowerShell 4.0
- SnippetPx module
- LanguagePx module

### License and Copyright

Copyright 2015 Provance Technologies

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

### Installing the ScsmMpcPx module

ScsmMpcPx is dependent on the LanguagePx and SnippetPx modules. You can download
and install the latest versions of ScsmMpcPx, LanguagePx and SnippetPx using any
of the following methods:

#### PowerShellGet

If you don't know what PowerShellGet is, it's the way of the future for PowerShell
package management. If you're curious to find out more, you should read this:
<a href="http://blogs.msdn.com/b/mvpawardprogram/archive/2014/10/06/package-management-for-powershell-modules-with-powershellget.aspx" target="_blank">Package Management for PowerShell Modules with PowerShellGet</a>

Note that these commands require that you have the PowerShellGet module installed
on the system where they are invoked.

TODO: COMING SOON (once this module is stable -- it is experimental right now; the
commands below do not work at the moment)

```powershell
# If you don’t have ScsmMpcPx installed already and you want to install it for all
# all users (recommended, requires elevation)
Install-Module ScsmMpcPx,LanguagePx,SnippetPx

# If you don't have ScsmMpcPx installed already and you want to install it for the
# current user only
Install-Module ScsmMpcPx,LanguagePx,SnippetPx -Scope CurrentUser

# If you have ScsmMpcPx installed and you want to update it
Update-Module
```

#### PowerShell 4.0 or Later

To install from PowerShell 4.0 or later, open a native PowerShell console (not ISE,
unless you want it to take longer), and invoke one of the following commands:

```powershell
# If you want to install ScsmMpcPx for all users or update a version already installed
# (recommended, requires elevation for new install for all users)
& ([scriptblock]::Create((iwr -uri http://tinyurl.com/Install-GitHubHostedModule).Content)) -ModuleName SnippetPx
& ([scriptblock]::Create((iwr -uri http://tinyurl.com/Install-GitHubHostedModule).Content)) -ModuleName ScsmMpcPx,LanguagePx -Branch master

# If you want to install ScsmMpcPx for the current user
& ([scriptblock]::Create((iwr -uri http://tinyurl.com/Install-GitHubHostedModule).Content)) -ModuleName SnippetPx -Scope CurrentUser
& ([scriptblock]::Create((iwr -uri http://tinyurl.com/Install-GitHubHostedModule).Content)) -ModuleName ScsmMpcPx,LanguagePx -Branch master -Scope CurrentUser
```

### How to load the module

To load the ScsmMpcPx module into PowerShell, invoke the following command:

```powershell
Import-Module -Name ScsmMpcPx
```

This command is not necessary if you are running Microsoft Windows
PowerShell 4.0 or later and if module auto-loading is enabled (default).

### ScsmMpcPx Commands

TODO

###  Creating Management Packs with ScsmMpcPx

TODO

### Command List

TODO