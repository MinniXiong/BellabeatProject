----------------------------------------------------------------------------------------------------------------------
-- Verify number of users
SELECT COUNT(DISTINCT Id)
FROM [BellabeatProject].[dbo].[DailyActivity_merged] -- there are 33

SELECT COUNT(DISTINCT Id)
FROM [BellabeatProject].[dbo].[DailySleep_merged] -- there are 24

SELECT COUNT(DISTINCT Id)
FROM [BellabeatProject].[dbo].[HourlySteps_merged] -- there are 33

----------------------------------------------------------------------------------------------------------------------
-- Check if there are duplciate entries with the same id and date
WITH RowNumCTE AS(
SELECT *,
ROW_NUMBER() OVER (
PARTITION BY Id, ActivityDate
ORDER BY Calories) row_num
FROM [BellabeatProject].[dbo].[DailyActivity_merged]) 
Select *
From RowNumCTE
Where row_num > 1
Order by Id
-- There are no duplicate entries in Daily Activity.
----------------------------------------------------
WITH RowNumCTE2 AS(
SELECT *,
ROW_NUMBER() OVER (
PARTITION BY Id, SleepDay
ORDER BY TotalSleepRecords) row_num
FROM [BellabeatProject].[dbo].[DailySleep_merged]) 
-- There are 3 duplicate entries in Daily Sleep. Remove them
DELETE
FROM RowNumCTE2
WHERE row_num > 1
----------------------------------------------------
WITH RowNumCTE3 AS(
SELECT *,
ROW_NUMBER() OVER (
PARTITION BY Id, ActivityHour
ORDER BY StepTotal) row_num
FROM [BellabeatProject].[dbo].[HourlySteps_merged]) 
Select *
From RowNumCTE3
Where row_num > 1
Order by Id
-- There are no duplicate entries in Hourly Steps.

----------------------------------------------------------------------------------------------------------------------
-- Convert SleepDay in DailySleep from date time to date.
SELECT CONVERT (Date, SleepDay)
FROM [BellabeatProject].[dbo].[DailySleep_merged]

ALTER TABLE [BellabeatProject].[dbo].[DailySleep_merged]
Add SleepDayConverted Date

UPDATE [BellabeatProject].[dbo].[DailySleep_merged]
SET SleepDayConverted = CONVERT (Date, SleepDay)

----------------------------------------------------------------------------------------------------------------------
-- Join Daily activity and Daily sleep
SELECT *
FROM [BellabeatProject].[dbo].[DailyActivity_merged] AS T1
FULL JOIN [BellabeatProject].[dbo].[DailySleep_merged] AS T2 ON
T1.Id = T2.Id
AND T1.ActivityDate = T2. SleepDayConverted

----------------------------------------------------------------------------------------------------------------------
-- Calculate average steps, calories and sleep per user
DROP TABLE if EXISTS #JoinTable
SELECT T1.Id, AVG(TotalSteps) AS AverageSteps, AVG(Calories) AS AverageCalories, AVG(TotalMinutesAsleep) AS AverageSleep
INTO #JoinTable -- Create a temp table
FROM [BellabeatProject].[dbo].[DailyActivity_merged] AS T1
FULL JOIN [BellabeatProject].[dbo].[DailySleep_merged] AS T2 ON
T1.Id = T2.Id
AND T1.ActivityDate = T2. SleepDayConverted
GROUP BY T1.Id

SELECT *
FROM #JoinTable
ORDER BY AverageCalories ASC
----------------------------------------------------------------------------------------------------------------------
-- Classify users based on number of steps
SELECT Id, AverageSteps,
CASE
WHEN AverageSteps < 4999 THEN 'Sedentary'
WHEN AverageSteps BETWEEN 5000 AND 7499 THEN 'LowActive'
WHEN AverageSteps BETWEEN 7500 AND 9999 THEN 'SomewhatActive'
WHEN AverageSteps > 10000 THEN 'Active'
WHEN AverageSteps > 12500 THEN 'HighlyActive'
END AS Active_type
INTO #ActiveTable
FROM #JoinTable

SELECT *
FROM #JoinTable
ORDER BY Id ASC
----------------------------------------------------------------------------------------------------------------------
-- Categorize users by sleep time
SELECT Id, AverageSleep,
CASE
WHEN AverageSleep < 419 THEN 'InsufficientSleep' 
WHEN AverageSleep > 420 THEN 'SufficientSleep'
END AS Sleep_Type
INTO #SleepTable
FROM #JoinTable
WHERE AverageSleep IS NOT NULL

----------------------------------------------------------------------------------------------------------------------
-- How much time do people spend in bed before going to sleep
ALTER TABLE [BellabeatProject].[dbo].[DailySleep_merged]
Add InBedTime int
UPDATE [BellabeatProject].[dbo].[DailySleep_merged]
SET InBedTime = TotalTimeInBed-TotalMinutesAsleep

DROP TABLE IF EXISTS #AvgBed
SELECT Id, AVG(InBedTime) AS AverageInBed
INTO #AvgBed
FROM [BellabeatProject].[dbo].[DailySleep_merged]
GROUP BY Id
ORDER BY AverageInBed DESC

SELECT *
FROM #AvgBed
----------------------------------------------------------------------------------------------------------------------
-- Join User type tables of activities and sleep
SELECT T1.Id,T1.Active_type, T2.Sleep_type
FROM #ActiveTable AS T1
JOIN #SleepTable AS T2 on
T1.Id = T2.Id
WHERE T2.Sleep_type='SufficientSleep'
ORDER BY T1.Active_type ASC


----------------------------------------------------------------------------------------------------------------------
-- Split date time in Hourly steps into Date and Time
SELECT *
FROM [BellabeatProject].[dbo].[HourlySteps_merged]

SELECT CONVERT(DATE,ActivityHour),CONVERT(TIME(0),ActivityHour)
FROM [BellabeatProject].[dbo].[HourlySteps_merged]

ALTER TABLE [BellabeatProject].[dbo].[HourlySteps_merged]
ADD StepDate Date, StepHour Time
UPDATE [BellabeatProject].[dbo].[HourlySteps_merged]
SET StepDate=CONVERT(DATE,ActivityHour), StepHour=CONVERT(TIME(0),ActivityHour)

SELECT StepHour,AVG(StepTotal) AS AverageStepPerHour
FROM [BellabeatProject].[dbo].[HourlySteps_merged]
GROUP BY StepHour
ORDER BY StepHour ASC

----------------------------------------------------------------------------------------------------------------------
-- Cateogrize users by their used days of app in one month
SELECT *
FROM [BellabeatProject].[dbo].[DailyActivity_merged]

SELECT Id, COUNT(DISTINCT ActivityDate) AS UsedDay
INTO #UsedDay
FROM [BellabeatProject].[dbo].[DailyActivity_merged]
GROUP BY Id

DROP TABLE IF EXISTS #MonthlyFreq
SELECT *,
CASE
WHEN UsedDay < 10 THEN 'InfrequentUser'
WHEN UsedDay BETWEEN 10 AND 20 THEN 'ModerateUser'
WHEN UsedDay > 21 THEN 'FrequentUser'
END AS FrequencyType
INTO #MonthlyFreq
FROM #UsedDay

SELECT *
FROM #MonthlyFreq
WHERE FrequencyType='ModerateUser'

----------------------------------------------------------------------------------------------------------------------
-- Total minutes worn by each user
DROP TABLE IF EXISTS #UsedMinute
SELECT Id, ActivityDate,
CONVERT(int,VeryActiveMinutes)+
CONVERT(int,FairlyActiveMinutes)+
CONVERT(int,LightlyActiveMinutes)+
CONVERT(int,SedentaryMinutes) AS UsedMinutes
INTO #UsedMinute
FROM [BellabeatProject].[dbo].[DailyActivity_merged]

SELECT Id, SUM(UsedMinutes)/COUNT(DISTINCT ActivityDate) AS AvgUsedMin
INTO #AvgUsedMin
FROM #UsedMinute
GROUP BY Id

SELECT *,
CASE
WHEN AvgUsedMin = 1440 THEN 'All Day'
WHEN AvgUsedMin BETWEEN 720 AND 1440 THEN 'More Than Half Day'
WHEN AvgUsedMin <720 THEN 'Less Than Half Day'
END AS FreqPerDay
FROM #AvgUsedMin -- This is not what we are looking for


SELECT *,
CASE
WHEN UsedMinutes = 1440 THEN 'All Day'
WHEN UsedMinutes BETWEEN 720 AND 1440 THEN 'More Than Half Day'
WHEN UsedMinutes <720 THEN 'Less Than Half Day'
END AS FreqPerDay
FROM #UsedMinute