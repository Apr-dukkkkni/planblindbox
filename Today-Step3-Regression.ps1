#Requires -Version 5.1
<#
  Today V0.1 black-box regression against a RUNNING LOCAL API.
  Creates one NEW task and one NEW habit for the selected user.
  It executes and grants real rewards: use a TEST user/database.
  Does not edit existing tasks/habits. -Cleanup archives only the newly created ones;
  completed records, asset balances and reward ledgers are intentionally retained.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:8080',
    [Parameter(Mandatory = $true)] [long]$UserId,
    [switch]$Cleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')
if ($UserId -le 0) { throw 'UserId must be positive' }
$createdTaskId = $null
$createdHabitId = $null

function Fail([string]$Message) { throw "FAILED: $Message" }
function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { Fail $Message }
}
function Check-Eq($Actual, $Expected, [string]$Message) {
    if ([string]$Actual -cne [string]$Expected) {
        Fail "$Message (actual='$Actual'; expected='$Expected')"
    }
}
function Api([string]$Method, [string]$Path, $Body = $null) {
    $requestParams = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        ErrorAction = 'Stop'
        TimeoutSec = 20
    }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 12 -Compress
        $requestParams['ContentType'] = 'application/json; charset=utf-8'
        $requestParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    $result = Invoke-RestMethod @requestParams
    Check-Eq $result.code 200 "$Method $Path response code"
    return $result.data
}
function Expect-Conflict([string]$Method, [string]$Path, $Body = $null) {
    $requestParams = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        ErrorAction = 'Stop'
        TimeoutSec = 20
    }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 12 -Compress
        $requestParams['ContentType'] = 'application/json; charset=utf-8'
        $requestParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    try {
        $null = Invoke-RestMethod @requestParams
    } catch {
        $response = $_.Exception.Response
        if ($null -eq $response) { throw }
        $statusCode = [int]$response.StatusCode
        Check-Eq $statusCode 409 "$Method $Path duplicate request HTTP status"
        return
    }
    Fail "$Method $Path unexpectedly succeeded (expected HTTP 409)"
}
function Today { return (Api 'GET' "/today?userId=$UserId") }
function Task-From($snapshot, [long]$id) {
    $found = @($snapshot.tasks | Where-Object { [long]$_.taskId -eq $id })
    Check-Eq $found.Count 1 "task $id must appear exactly once in Today"
    return $found[0]
}
function Habit-From($snapshot, [long]$id) {
    $found = @($snapshot.habits | Where-Object { [long]$_.habitId -eq $id })
    Check-Eq $found.Count 1 "habit $id must appear exactly once in Today"
    return $found[0]
}
function Iso-Date($value) {
    if ($value -is [datetime]) { return $value.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
    return [string]$value
}
function Check-Date($snapshot, [string]$date) {
    Check-Eq (Iso-Date $snapshot.date) $date 'Server day changed during test; rerun away from midnight'
}
function Check-AssetDelta($before, $after, $reward, [string]$stage) {
    Require ($null -ne $reward) "$stage reward response missing"
    Check-Eq ([long]$after.coin - [long]$before.coin) ([long]$reward.coin) "$stage coin delta"
    Check-Eq ([long]$after.exp - [long]$before.exp) ([long]$reward.exp) "$stage exp delta"
    Check-Eq ([long]$after.water - [long]$before.water) ([long]$reward.water) "$stage water delta"
    if ($reward.granted) {
        Check-Eq $after.coin $reward.coinBalance "$stage coin balance"
        Check-Eq $after.exp $reward.expBalance "$stage exp balance"
        Check-Eq $after.water $reward.waterBalance "$stage water balance"
    } else {
        Check-Eq $reward.coin 0 "$stage disabled coin"
        Check-Eq $reward.exp 0 "$stage disabled exp"
        Check-Eq $reward.water 0 "$stage disabled water"
    }
}
function Check-Summary($snapshot, [int]$taskTotal, [int]$taskDone, [int]$habitTotal, [int]$habitDone) {
    $summary = $snapshot.summary
    Check-Eq $summary.taskTotal $taskTotal 'taskTotal'
    Check-Eq $summary.taskCompleted $taskDone 'taskCompleted'
    Check-Eq $summary.habitTotal $habitTotal 'habitTotal'
    Check-Eq $summary.habitCheckedIn $habitDone 'habitCheckedIn'
    $all = $taskTotal + $habitTotal
    $expectedRate = if ($all -eq 0) { 0.0 } else { [Math]::Round(100.0 * ($taskDone + $habitDone) / $all, 2, [MidpointRounding]::AwayFromZero) }
    Require ([Math]::Abs([double]$summary.completionRate - $expectedRate) -lt 0.001) "completionRate: expected $expectedRate, got $($summary.completionRate)"
}

try {
    Write-Host '[1/8] Read baseline Today and balances'
    $baseline = Today
    $date = Iso-Date $baseline.date
    Require ($date -match '^\d{4}-\d{2}-\d{2}$') "Today.date must be yyyy-MM-dd; got $date"
    $nextDay = [datetime]::ParseExact($date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).AddDays(1).ToString('yyyy-MM-dd')
    $tag = (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)

    Write-Host '[2/8] Create task target=2 and DAILY habit (only fresh data)'
    $task = Api 'POST' '/tasks' @{
        userId = $UserId; title = "Today-E2E-Task-$tag"; note = 'Automated regression test'
        startTime = "${date}T00:00:00"; endTime = "${nextDay}T23:59:59"; targetCount = 2
    }
    $createdTaskId = [long]$task.taskId
    Require ($createdTaskId -gt 0) 'POST /tasks did not return taskId'
    $habit = Api 'POST' '/habits' @{
        userId = $UserId; name = "Today-E2E-Habit-$tag"; note = 'Automated regression test'
        startDate = $date; repeatRule = @{ type = 'DAILY' }
    }
    $createdHabitId = [long]$habit.habitId
    Require ($createdHabitId -gt 0) 'POST /habits did not return habitId'
    $created = Today
    Check-Date $created $date
    $newTask = Task-From $created $createdTaskId
    $newHabit = Habit-From $created $createdHabitId
    Check-Eq $newTask.status 'PENDING' 'new task status'
    Check-Eq $newTask.totalActualCount 0 'new task total'
    Check-Eq $newTask.todayActualCount 0 'new task today'
    Check-Eq $newTask.remainingCount 2 'new task remaining'
    Require (-not $newHabit.checkedInToday) 'new habit should be unchecked'
    Check-Summary $created ([int]$baseline.summary.taskTotal + 1) ([int]$baseline.summary.taskCompleted) ([int]$baseline.summary.habitTotal + 1) ([int]$baseline.summary.habitCheckedIn)
    Check-Eq $created.assets.coin $baseline.assets.coin 'creation must not grant coins'
    Check-Eq $created.assets.exp $baseline.assets.exp 'creation must not grant exp'
    Check-Eq $created.assets.water $baseline.assets.water 'creation must not grant water'

    Write-Host '[3/8] Complete one of two units; reward must be absent'
    $partial = Api 'POST' "/tasks/$createdTaskId/complete?userId=$UserId" @{ actualCount = 1 }
    Check-Eq $partial.status 'IN_PROGRESS' 'partial status'
    Check-Eq $partial.todayActualCount 1 'partial today progress'
    Check-Eq $partial.totalActualCount 1 'partial cumulative progress'
    Check-Eq $partial.remainingCount 1 'partial remaining progress'
    Require ($null -eq $partial.reward) 'partial completion must NOT settle reward'
    $afterPartial = Today
    Check-Date $afterPartial $date
    $partialToday = Task-From $afterPartial $createdTaskId
    Check-Eq $partialToday.todayActualCount 1 'Today partial todayActualCount'
    Check-Eq $partialToday.totalActualCount 1 'Today partial totalActualCount'
    Require (-not $partialToday.completedToday) 'partial task marked completedToday'
    Check-Eq $afterPartial.assets.coin $created.assets.coin 'partial coin balance'
    Check-Eq $afterPartial.assets.exp $created.assets.exp 'partial exp balance'
    Check-Eq $afterPartial.assets.water $created.assets.water 'partial water balance'

    Write-Host '[4/8] Complete final unit; Today must show completedToday and reward'
    $done = Api 'POST' "/tasks/$createdTaskId/complete?userId=$UserId" @{ actualCount = 1 }
    Check-Eq $done.status 'COMPLETED' 'final task status'
    Check-Eq $done.todayActualCount 2 'final task today count'
    Check-Eq $done.totalActualCount 2 'final task cumulative count'
    Check-Eq $done.remainingCount 0 'final task remaining count'
    $afterTask = Today
    Check-Date $afterTask $date
    $taskView = Task-From $afterTask $createdTaskId
    Require ([bool]$taskView.completedToday) 'Today task must show completedToday=true'
    Check-Eq $taskView.status 'COMPLETED' 'Today task status'
    Check-Eq $taskView.todayActualCount 2 'Today task todayActualCount'
    Check-Eq $taskView.totalActualCount 2 'Today task totalActualCount'
    Check-Eq $taskView.remainingCount 0 'Today task remainingCount'
    Check-AssetDelta $afterPartial.assets $afterTask.assets $done.reward 'task'
    Check-Summary $afterTask ([int]$baseline.summary.taskTotal + 1) ([int]$baseline.summary.taskCompleted + 1) ([int]$baseline.summary.habitTotal + 1) ([int]$baseline.summary.habitCheckedIn)

    Write-Host '[5/8] Duplicate task completion must be rejected (HTTP 409)'
    Expect-Conflict 'POST' "/tasks/$createdTaskId/complete?userId=$UserId" @{ actualCount = 1 }
    $afterDuplicateTask = Today
    Check-Date $afterDuplicateTask $date
    Check-Eq $afterDuplicateTask.assets.coin $afterTask.assets.coin 'duplicate task coins'
    Check-Eq $afterDuplicateTask.assets.exp $afterTask.assets.exp 'duplicate task exp'
    Check-Eq $afterDuplicateTask.assets.water $afterTask.assets.water 'duplicate task water'
    Check-Eq (Task-From $afterDuplicateTask $createdTaskId).totalActualCount 2 'duplicate task progress'

    Write-Host '[6/8] Check in habit; reward, streak and Today must update'
    $checkIn = Api 'POST' "/habits/$createdHabitId/check-in?userId=$UserId"
    Require ([bool]$checkIn.checkedInToday) 'check-in response checkedInToday is false'
    Check-Eq $checkIn.totalCheckInDays 1 'new habit totalCheckInDays'
    Check-Eq $checkIn.currentStreak 1 'new habit currentStreak'
    $afterHabit = Today
    Check-Date $afterHabit $date
    $habitView = Habit-From $afterHabit $createdHabitId
    Require ([bool]$habitView.checkedInToday) 'Today habit checkedInToday is false'
    Check-Eq $habitView.currentStreak 1 'Today habit current streak'
    Check-Eq $habitView.totalCheckInDays 1 'Today habit check-in days'
    Check-AssetDelta $afterDuplicateTask.assets $afterHabit.assets $checkIn.reward 'habit'
    Check-Summary $afterHabit ([int]$baseline.summary.taskTotal + 1) ([int]$baseline.summary.taskCompleted + 1) ([int]$baseline.summary.habitTotal + 1) ([int]$baseline.summary.habitCheckedIn + 1)

    Write-Host '[7/8] Duplicate check-in must be rejected (HTTP 409)'
    Expect-Conflict 'POST' "/habits/$createdHabitId/check-in?userId=$UserId"
    $afterDuplicateHabit = Today
    Check-Date $afterDuplicateHabit $date
    Check-Eq $afterDuplicateHabit.assets.coin $afterHabit.assets.coin 'duplicate habit coins'
    Check-Eq $afterDuplicateHabit.assets.exp $afterHabit.assets.exp 'duplicate habit exp'
    Check-Eq $afterDuplicateHabit.assets.water $afterHabit.assets.water 'duplicate habit water'
    Check-Eq (Habit-From $afterDuplicateHabit $createdHabitId).totalCheckInDays 1 'duplicate habit days'

    Write-Host '[8/8] Two read-only Today requests must not mutate result or assets'
    $read1 = Today
    $read2 = Today
    Check-Date $read1 $date
    Check-Date $read2 $date
    $serialized1 = ConvertTo-Json -InputObject $read1 -Depth 20 -Compress
    $serialized2 = ConvertTo-Json -InputObject $read2 -Depth 20 -Compress
    Check-Eq $serialized2 $serialized1 'Two consecutive GET /today responses differ'

    Write-Host ''
    Write-Host 'PASS: All 8 HTTP regression stages succeeded.' -ForegroundColor Green
    Write-Host "testUserId=$UserId taskId=$createdTaskId habitId=$createdHabitId date=$date"
    Write-Host "Task reward=$($done.reward | ConvertTo-Json -Compress)"
    Write-Host "Habit reward=$($checkIn.reward | ConvertTo-Json -Compress)"
    Write-Host 'Use the SQL in the companion guide to check records and reward ledgers.'
} finally {
    if ($Cleanup) {
        if ($null -ne $createdTaskId) {
            try { $null = Api 'DELETE' "/tasks/${createdTaskId}?userId=$UserId"; Write-Host "Archived NEW task $createdTaskId" }
            catch { Write-Warning "Could not archive task ${createdTaskId}: $_" }
        }
        if ($null -ne $createdHabitId) {
            try { $null = Api 'DELETE' "/habits/${createdHabitId}?userId=$UserId"; Write-Host "Archived NEW habit $createdHabitId" }
            catch { Write-Warning "Could not archive habit ${createdHabitId}: $_" }
        }
        Write-Warning 'Cleanup archives definitions only; execution history and awarded assets are preserved.'
    }
}
