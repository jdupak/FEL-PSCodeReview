Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

class Remark {
    [string]$kind
    [string]$file
    [int]$line
    [float]$points
    [string]$comment

    Remark(
        [string]$kind,
        [string]$file,
        [int]$line,
        [float]$points,
        [string]$comment
    ) {
        $this.kind = $kind
        $this.file = $file
        $this.line = $line
        $this.points = $points
        $this.comment = $comment
    }

    [string]FormatAsHtml() {
        return "<tr><td><a href=`"#remark-l$($_.line)`">$($_.file):$($_.line)</a> <td class=`"remark-points`"> $($_.points)b <td> $($_.comment)"
    }

    [string]FormatAsPlainText() {
        return "$($_.file):$($_.line)`t$($_.points)b`t$($_.comment)"
    }
}

class Remarks {
    [Remark[]]$items

    Remarks() {
        $this.items = @()
    }
    
    Add(
        [string]$kind,
        [string]$file,
        [int]$line,
        [float]$points,
        [string]$comment
    ) {
        $this.items += [Remark]::new($kind, $file, $line, $points, $comment)
    }

    [float] TotalPoints() {
        return - ($this.items | Measure-Object -Property points -Sum).Sum
    }

    [string] FormatAsPlainText() {
        return $this.items | % { $_.FormatAsPlainText() } | Join-String -Separator "`n"
    }

    [string] FormatAsHtmlTable() {
        return @(
            "<table class=`"remark-list`">"
            ($this.items | % { $_.FormatAsHtml() } | Join-String -Separator "`n")
            "</table>"
        ) -join "`n"
    }
}

function New-CodeReview([string]$file) {
    $css = chroma --style=colorful --html-styles

    $remarks = [Remarks]::new()
    $summary, $body = New-FileReview $file $remarks
    
    Write-Host $summary
    Write-Host "Soucasti hodnoceni je PDF s komentari. Souhrn komentaru:"
    Write-Host $remarks.FormatAsPlainText()
    Write-Host "======================="
    Write-Host "Total points deducted: $(-($remarks.TotalPoints().toString("#.##")))"    
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
            max-width: 1000px;
        }

        table {
            margin: 0 auto;
            border: 1px solid grey;
            border-collapse: collapse;
        }

        th,td {
            padding: .5em;
            border: 1px solid lightgrey;
        }

        .review {
            display: grid;
            grid-template-columns: 70% 30%;
            align-items: end;
        
        }

        .remark {
            margin: 10px 0 0 10px;
            padding: 5px 10px;
            font-size: 0.9rem;
            border: solid 2px gray;
            background: white;
        }

        .remark-title {
            display: inline;
            margin: 0;
            padding: 0 0 5px 0;
            font-wight: bold;
            font-size: 90%;
            color: gray;
        }

        .remark--negative {
            border-color: red;
        }

        .remark--negative .remark-title {
            color: red;
        }

        .remark--positive {
            border-color: green;
        }

        .remark--positive .remark-title {
            color: green;
        }

        .remark-points {
            text-align: right;
        }

        .chroma {
            margin: 0;
        }

        ${css}
    </style>
</head>
<body>
    <main>
        <h1>Code Review Result Details</h1>
        <div class="summary">$summary </div>
        <div class="total">Total points deducted: $(-($remarks.TotalPoints().tostring("#.##")))</div>
        <h2>List of Remarks</h2>
        $($remarks.FormatAsHtmlTable())
        <h2>$file</h2>
        <div class="review">
            $body
        </div>
    </main>
    </body>
    </html>
"@
}

function New-FileReview([string] $file, [Remarks] $remarks) {
    $code = Get-Content -Raw $file
    
    if (!$code.StartsWith("/*$")) {
        throw "This is not a valid input file. Summary comment /*$ ... $*/ at the begining of a file is required."
    }

    $code = $code.Substring(4)
    $summary, $code = $code -split "\$\*/", 2
    $body = New-FileReviewBody "$code`n//" $file $remarks

    return $summary, $body[0..($body.count - 3)] # Hide last lightlited line, which was artificially added.
}

function New-FileReviewBody([string]$content, [string]$filename, [Remarks]$remarks) {
    [int]$lastLineNum = 0
    ($content -split "(//\$.*)`n?") | % {
        if ($_.StartsWith("//$")) {
            if ($_ -match "//\$-\s*(?<Severnity>\d+.?\d*)\s*(?<Comment>.+)") {
                $remarks.Add("negative", $filename, ($lastLineNum - 1), - [float]$Matches["Severnity"], $Matches["Comment"])
            }
            elseif ($_ -match "//\$\+\s*(?<Comment>.+)") {
                $remarks.Add("positive", $filename, ($lastLineNum - 1), 0.0, $Matches["Comment"])
            }
            elseif ($_ -match "//\$\s*(?<Comment>.+)") {
                $remarks.Add("neutral", $filename, ($lastLineNum - 1), 0.0, $Matches["Comment"])
            }
            else {
                throw "MalformedComment"
            }
            Format-Remark $remarks.items[-1]
        }
        else {
            Format-CodeSegment $_ ([ref]$lastLineNum)
        }
    }
}

function Format-Remark([Remark] $remark) {
    @"
    <div class="remark remark--$($remark.kind)" id="remark-l$($remark.line)">
    <h3 class="remark-title">! $(if ($remark.points -ne 0.0) { $remark.points })</h3>
    $($remark.comment)
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