package run.plainstride.core.database

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Entity(tableName="cycle_preferences",primaryKeys=["accountId"])
data class CyclePreferenceEntity(val accountId:String,val enabled:Boolean)

@Entity(tableName="cycle_wellbeing",primaryKeys=["accountId","logId"],indices=[Index(value=["accountId","recordedAtEpochMs"])])
data class CycleWellbeingEntity(val accountId:String,val logId:String,val recordedAtEpochMs:Long,val bleeding:Boolean,val energy:Int,val discomfort:Int)

@Dao interface CycleWellbeingDao {
 @Query("SELECT * FROM cycle_preferences WHERE accountId=:accountId LIMIT 1") suspend fun preference(accountId:String):CyclePreferenceEntity?
 @Insert(onConflict=OnConflictStrategy.REPLACE) suspend fun setPreference(value:CyclePreferenceEntity)
 @Query("SELECT * FROM cycle_wellbeing WHERE accountId=:accountId ORDER BY recordedAtEpochMs DESC LIMIT :limit") suspend fun logs(accountId:String,limit:Int=90):List<CycleWellbeingEntity>
 @Insert(onConflict=OnConflictStrategy.REPLACE) suspend fun insert(value:CycleWellbeingEntity)
 @Query("DELETE FROM cycle_wellbeing WHERE accountId=:accountId") suspend fun deleteLogs(accountId:String)
 @Query("DELETE FROM cycle_preferences WHERE accountId=:accountId") suspend fun deletePreference(accountId:String)
}
