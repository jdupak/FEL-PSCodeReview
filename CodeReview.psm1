Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

class CodeFragment {
    [int] $StartLine
    [string] $Code

    CodeFragment(
        [int] $StartLine,
        [string] $Code
    ) {
        $this.StartLine = $StartLine
        $this.Code = $Code
    }

    [int] GetLineCount() {
        return $this.Code.Split("`n").Count
    }

    [string] FormatAsHtml([Nullable[int]] $HighlightedLine) {
        return $this.Code | chroma --lexer=c --html --html-only --html-lines --html-base-line=$($this.StartLine) --html-highlight=$($HighlightedLine)
    }
}

class Remark {
    [string] hidden $Kind
    [string] $File
    [int] $Line
    [float] $Points
    [string] $Comment
    [CodeFragment] hidden $Code # Code preceeding this remarks (from last remark)

    Remark(
        [string] $Kind,
        [string] $File,
        [int] $Line,
        [float] $Points,
        [string] $Comment,
        [CodeFragment] $Code
    ) {
        $this.Kind = $Kind
        $this.File = $File
        $this.Line = $Line
        $this.Points = $Points
        $this.Comment = $Comment
        $this.Code = $Code
    }

    [string] FormatAsHtml() {
        return "<tr><td><a href=`"#remark-l$($_.line)`">$($_.file):$($_.line)</a> <td class=`"remark-points`"> $($_.points)b <td> $($_.comment)"
    }

    [string] FormatAsText() {
        return "$($_.file):$($_.line)`t$($_.points)b`t$($_.comment)"
    }

    [string] FormatCommentAsHtml() {
        return @"
        <div class="remark remark--$($this.Kind)" id="remark-l$($this.Line)">
        <h3 class="remark-title">! $(if ($this.Points -ne 0.0) { $this.Points })</h3>
        $($this.Comment)
        </div>
"@
    }

    [string] FormatAsCodeFragment() {
        return $this.Code.FormatAsHtml($this.Line) + $this.FormatCommentAsHtml()
    }
}

class FileReview {
    [string] $FileName
    [string] $Summary
    [Remark[]] $Remarks
    [CodeFragment] hidden $LastCode

    FileReview([string] $FileName, [string] $Summary) {
        $this.FileName = $FileName
        $this.Summary = $Summary
        $this.Remarks = @()
    }
    
    Add(
        [string] $Kind,
        [string] $File,
        [int] $Line,
        [float] $Points,
        [string] $Comment,
        [CodeFragment] $Code
    ) {
        $this.Remarks += [Remark]::new($Kind, $File, $Line, $Points, $Comment, $Code)
    }

    [float] TotalPoints() {
        return ($this.Remarks | Measure-Object -Property points -Sum).Sum
    }

    [string] FormatTotalPoints() {
        return "$($this.TotalPoints().ToString("0.##"))b"
    }

    [string] FormatListAsMarkdown() {
        return $this.Remarks | % { "- $($_.FormatAsText())" } | Join-String -Separator "`n"
    }

    [string] FormatListAsHtml() {
        return @(
            "<table class=`"remark-list`">"
            ($this.Remarks | % { $_.FormatAsHtml() } | Join-String -Separator "`n")
            "</table>"
        ) -join "`n"
    }

    [string] FormatAsHtml() {
        $out = "<h2>File: $($this.FileName)</h2>"
        $out += "<div class=`"review`">"
        foreach ($Remark in $this.Remarks) {
            $out += $Remark.FormatAsCodeFragment()
            $out += "`n"
        }
        $out += $this.LastCode.FormatAsHtml($null)
        $out += "</div>"
        return $out
    }

    [string] FormatEvalSummary() {
        return @"
*NOTE: Soucasti hodnoceni je PDF s detaily.*

**Summary:**
$($this.Summary)

$($this.FormatListAsMarkdown())
        
"@
    }
}

function New-CodeReview([string]$FileName) {
    $Review = New-FileReview $FileName
    
    $Eval = $Review.FormatEvalSummary()
        
    $Html = @"
<!html>
<head>
    <style>
        $(Get-Content -Raw (Join-Path -Path $ScriptDir -ChildPath "./CodeReview.css"))
        $(chroma --style=colorful --html-styles)
    </style>
</head>
<body>
    <main>
        <h1>Code Review Result Details</h1>
        <div class="summary">$($Review.Summary)</div>
        <h2>Total manual score</h2> <b>$($Review.FormatTotalPoints())</b>
        <h2>List of Remarks</h2>
        $($Review.FormatListAsHtml())
        $($Review.FormatAsHtml())
    </main>
    </body>
    </html>
"@
    return $Review, $Eval, $Html
}

function Get-FileSections([string] $FileName) {
    $Code = Get-Content -Raw $FileName
    
    if (!$Code.StartsWith("/*$")) {
        throw "This is not a valid input file. Summary comment /*$ ... $*/ at the begining of a file is required."
    }

    $Code = $Code.Substring(4)
    $Summary, $Code = $Code -split "\$\*/", 2

    return $Summary, $Code
}

function New-FileReview([string] $FileName) {
    $Summary, $Code = Get-FileSections $FileName

    $Review = [FileReview]::new($FileName, $Summary)

    $LastCode = [CodeFragment]::new(0, "")
    $LastLineNum = 0

    foreach ($_ in ($Code -split "(//\$.*)`n?")) {
        if ($_.StartsWith("//$")) {
            if ($_ -match "//\$-\s*(?<Severnity>\d*\.?\d*)\s*(?<Comment>.+)") {
                $Review.Add("negative", $FileName, $LastLineNum, - [float]$Matches["Severnity"], $Matches["Comment"], $LastCode)
            }
            elseif ($_ -match "//\$\+\s*(?<Severnity>\d*\.?\d*)\s*(?<Comment>.+)") {
                $Review.Add("positive", $FileName, $LastLineNum, + [float]$Matches["Severnity"], $Matches["Comment"], $LastCode)
            }
            elseif ($_ -match "//\$\s*(?<Comment>.+)") {
                $Review.Add("neutral", $FileName, $LastLineNum, 0.0, $Matches["Comment"], $LastCode)
            }
            else {
                throw "Comment at line $($LastLineNum) does not match any known format ($($_))."
            }
        }
        else {
            $LastCode = [CodeFragment]::new($LastLineNum + 1, $_)
            $lastLineNum += $LastCode.GetLineCount()
        }
    }

    $Review.LastCode = $LastCode

    return $Review
}

function Initialize-CodeReview([string]$file = "main.c") {
    $(
    "/*$"
    "$*/"
    (Get-Content $file -Raw)
) | Set-Content $file

    @"
    cmake_minimum_required(VERSION 3.23)
    project(codereview C)

    set(CMAKE_C_STANDARD 11)

    add_executable(main $($file))
"@ | Set-Content CMakeLists.txt
}

function Build-CodeReview([string]$file = "main.c") {
    $Review, $Eval, $Html = New-CodeReview $file
    
    $Review.Remarks
    [PSCustomObject]@{
        Total = $Review.FormatTotalPoints()
    } | Format-List

    Write-Output $Html > output.html
    microsoft-edge-dev --headless --disable-gpu --print-to-pdf --print-to-pdf-no-header ./output.html 2>/dev/null
    Write-Output $Eval > eval.txt
    Write-Output $Review.FormatTotalPoints()  > "manual-score.txt"
}

function Publish-BruteCodeReview() {
    Build-CodeReview
    Write-Host "Upload to BRUTE?"
    pause
    Publish-BruteEvaluationFromFiles
    if ((Get-Content -Raw .BRUTE-URL.txt) -match "https://cw.felk.cvut.cz/brute/teacher/upload/(?<Upload>\d+)/(?<Team>\d+)") {
        Invoke-BruteResultFileUpload "./output.pdf" $Matches["Upload"] $Matches["Team"]
    } else {
        Write-Error "PDF not uploaded!"
    }
}

function Start-BruteCodeReview(
    [Parameter(Mandatory)][ValidateSet([_StudentName])][string]$UserName
) {
    Initialize-BruteEvaluation (Split-Path -Path (Get-Location) -Leaf) $UserName ..
    Set-Location $UserName
    Initialize-CodeReview
    clion .
}