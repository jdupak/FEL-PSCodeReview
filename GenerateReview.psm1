Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

class Remark {
    [string]$file
    [int]$line
    [float]$points
    [string]$comment

    Remark(
        [string]$file,
        [int]$line,
        [float]$points,
        [string]$comment
    ) {
        $this.file = $file
        $this.line = $line
        $this.points = $points
        $this.comment = $comment
    }

    [string]FormatHtmlTable() {
        return "<tr><td><a href=`"#remark-l$($_.line)`">$(($_.file -split "/")[2]):$($_.line)</a> <td> $($_.points)b <td> $($_.comment)"
    }

    [string]FormatPlain() {
        return "$(($_.file -split "/")[2]):$($_.line)`t$($_.points)b`t$($_.comment)"
    }
}

class Remarks {
    [Remark[]]$items

    Remarks() {
        $this.items = @()
    }
    
    Add(
        [string]$file,
        [int]$line,
        [float]$points,
        [string]$comment
    ) {
        $this.items += [Remark]::new($file, $line, $points, $comment)
    }

    [float]DeducedPoints() {
        return $(-($this.items | Measure-Object -Property points -Sum).Sum)
    }
}

function ProcessCode([String]$code, [string]$filename) {
    $css = chroma --style=colorful --html-styles

    if (!$code.StartsWith("/*$")) {
        throw "This is not a valid input file:`n$code"
    }
    $code = $code.Substring(4)
    $summary, $code = $code -split "\$\*/", 2
    $remarks = [Remarks]::new()
    $body = Process-SourceFile $code $filename ($remarks)

    Write-Host $summary
    Write-Host "Soucasti hodnoceni je PDF s komentari. Souhrn komentaru:"
    $remarks.items | % { Write-Host $_.FormatPlain() }
    Write-Host "======================="
    Write-Host "Total points deducted: $(-($remarks.DeducedPoints().toString("#.##")))"
    @"
<!html>
<head>
    <style>
        body {
            margin: 0;
            padding: 0;
            font-family: sans-serif;
            background: white;
        }

        main {
            padding: 0 20px;
            max-width: 750px;
        }

        .remark {
            margin: 10px 20px;
            padding: 10px;
            font-size: 0.9rem;
            border: solid 2px gray;
        }

        .remark-title {
            display: inline;
            margin: 0;
            padding: 0 0 5px 0;
            font-wight: bold;
            font-size: 90%;
            color: gray;
        }

        .remark--red {
            border-color: red;
        }

        .remark--red .remark-title {
            color: red;
        }

        .remark--green {
            border-color: green;
        }

        .remark--green .remark-title {
            color: green;
        }

        ${css}
    </style>
</head>
<body>
    <main>
        <h1>Code Review Result Details</h1>
        <div class="summary">$summary </div>
        <div class="total">Total points deducted: $(-($remarks.DeducedPoints().tostring("#.##")))</div>
        <h2>List of Remarks</h2>
        <table class="remark-list">
    $($remarks.items | % {
        "<tr><td><a href=`"#remark-l$($_.line)`">$(($_.file -split "/")[2]):$($_.line)</a> <td> $($_.points)b <td> $($_.comment)"
    })
    </table>
    <h2>$filename</h2>
    $body
    </main>
    </body>
    </html>
"@
}

function Process-SourceFile([string]$content, [string]$filename, [Remarks]$remarks) {
    [int]$lastLineNum = 0
    ($code -split "(//\$.*)`n?") | % {
        if ($_.StartsWith("//$")) {
            if ($_ -match "//\$-\s*(?<Severnity>\d+.?\d*)\s*(?<Comment>.+)") {
                Format-Remark "red" $Matches["Comment"] ($lastLineNum - 1)
                $remarks.Add($filename, ($lastLineNum - 1), - [float]$Matches["Severnity"], $Matches["Comment"])
            }
            elseif ($_ -match "//\$\+\s*(?<Comment>.+)") {
                Format-Remark "green" $Matches["Comment"] ($lastLineNum - 1)
                $remarks.Add($filename, ($lastLineNum - 1), 0.0, $Matches["Comment"])
            }
            elseif ($_ -match "//\$\s*(?<Comment>.+)") {
                Format-Remark "neutral" $Matches["Comment"] ($lastLineNum - 1)
                $remarks.Add($filename, ($lastLineNum - 1), 0.0, $Matches["Comment"])
            }
            else {
                throw "MalformedComment"
            }
        }
        else { 
            Format-CodeSegment $_ ([ref]$lastLineNum)
        }
    }
}

function Format-Remark([string]$kind, [string]$text, [int]$line) {
    @"
    <div class="remark remark--$kind" id="remark-l$line">
    <h3 class="remark-title">Remark</h3>
    $text
    </div>
"@
}

function Format-CodeSegment([string]$segment, [ref][int]$lastLineNum) {
    [int]$lineNum = $lastLineNum.Value
    $linesInSegment = $segment.Split("`n").Count
    $lastLineInSegment = $lineNum + $linesInSegment - 1
    Write-Output $segment | chroma --lexer=c --html --html-only --html-lines --html-base-line=$lineNum --html-highlight=$lastLineInSegment
    $lastLineNum.Value += $linesInSegment
}


Export-ModuleMember ProcessCode