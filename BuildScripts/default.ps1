$psake.use_exit_on_error = $true
properties {
    $baseDir = (Split-Path -parent $psake.build_script_dir)
    $versionTag = git describe --abbrev=0 --tags
    $version = $versionTag + "."
    $version += (git log $($version + '..') --pretty=oneline | measure-object).Count
    $changeset=(git log -1 $($versionTag + '..') --pretty=format:%H)
    $nugetExe = "$env:ChocolateyInstall\ChocolateyInstall\nuget"
}

Task default -depends Build
Task Build -depends Test, Package
Task Deploy -depends Test, Package, Push-Nuget -description 'Versions, packages and pushes to Myget'
Task Package -depends Version-Module, Pack-Nuget -description 'Versions the psd1 and packs the module and example package'

Task Test {
    pushd "$baseDir"
    exec {."$env:ChocolateyInstall\lib\Pester.1.2.1\tools\bin\Pester.bat" $baseDir/Tests -DisableLegacyExpectations}
    popd
}

Task Version-Module -description 'Stamps the psd1 with the version and last changeset SHA' {
    Get-ChildItem "$baseDir\**\*.psd1" | % {
       $path = $_
        (Get-Content $path) |
            % {$_ -replace "^ModuleVersion = '.*'`$", "ModuleVersion = '$version'" } | 
                % {$_ -replace "^PrivateData = '.*'`$", "PrivateData = '$changeset'" } | 
                    Set-Content $path
    }
}

Task Pack-Nuget -description 'Packs the modules and example packages' {
    if (Test-Path "$baseDir\buildArtifacts") {
      Remove-Item "$baseDir\buildArtifacts" -Recurse -Force
    }
    if (Test-Path "$baseDir\buildPackages\*.nupkg") {
      Remove-Item "$baseDir\buildPackages\*.nupkg" -Force
    }
    mkdir "$baseDir\buildArtifacts"

    PackDirectory "$baseDir\BuildPackages"
    PackDirectory "$baseDir\nuget"
    Move-Item "$baseDir\nuget\*.nupkg" "$basedir\buildArtifacts"
}

Task Push-Nuget -description 'Pushes the module to Myget feed' {
    $pkg = Get-Item -path $baseDir\buildPackages\example.*.*.*.nupkg
    exec { cpush $pkg.FullName -source "http://www.myget.org/F/boxstarter/api/v2/package" }
    $pkg = Get-Item -path $baseDir\buildPackages\example-light.*.*.*.nupkg   
    exec { cpush $pkg.FullName -source "http://www.myget.org/F/boxstarter/api/v2/package" }
    $pkg = Get-Item -path $baseDir\buildArtifacts\boxstarter.*.*.*.nupkg   
    exec { cpush $pkg.FullName -source "http://www.myget.org/F/boxstarter/api/v2/package" }
    $pkg = Get-Item -path $baseDir\buildArtifacts\boxstarter.helpers.*.*.*.nupkg   
    exec { cpush $pkg.FullName -source "http://www.myget.org/F/boxstarter/api/v2/package" }
}

Task Push-Chocolatey -description 'Pushes the module to Chocolatey feed' {
    $pkg = Get-Item -path $baseDir\buildArtifacts\boxstarter.0.*.*.nupkg   
    exec { cpush $pkg.FullName }
    $pkg = Get-Item -path $baseDir\buildArtifacts\boxstarter.helpers.*.*.*.nupkg   
    exec { cpush $pkg.FullName }
}

function PackDirectory($path){
    exec { 
        Get-ChildItem "$path\**\*.nuspec" | 
            % { .$nugetExe pack $_ -OutputDirectory $path -NoPackageAnalysis -version $version }
    }
}