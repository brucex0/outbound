package com.plainstride.outbound.feature.community.planning

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

data class PlannerState(
    val activity: PlannerActivity, val targetDistanceM: Double?, val start: PlannerPlace? = null,
    val via: PlannerPlace? = null, val lessClimbing: Boolean = false,
    val candidates: List<PlannerCandidate> = emptyList(), val selected: PlannerCandidate? = null,
    val searchResults: List<PlannerPlace> = emptyList(), val busy: Boolean = false, val accepting: Boolean = false,
    val generationUnavailable: Boolean = false, val completed: Boolean = false, val message: PlannerMessage? = null,
)
enum class PlannerMessage { FAILED, LOCATION_UNAVAILABLE, NO_PLACES, INVALID_DISTANCE, SAVE_FAILED }
/** One request revision guards every asynchronous write, including place lookup and acceptance. */
class RoutePlannerSession(private val accountId: String, activity: PlannerActivity, initialDistanceM: Double?, private val services: PlannerServices, private val scope: CoroutineScope) {
    private val mutable = MutableStateFlow(PlannerState(activity, initialDistanceM))
    val state: StateFlow<PlannerState> = mutable.asStateFlow()
    private val accountCurrent=services.accountGuard(accountId)
    private var revision = 0L
    private var job: Job? = null
    private var seed = kotlin.random.Random.nextInt(1, 1000000)
    init { services.event("opened",activity) }
    private fun invalidate(): Long { job?.cancel(); return ++revision }
    private fun valid(value: Long) = value == revision && accountCurrent()
    fun edit(distance: Double? = state.value.targetDistanceM, start: PlannerPlace? = state.value.start, via: PlannerPlace? = state.value.via, lessClimbing: Boolean = state.value.lessClimbing) {
        invalidate(); mutable.value = state.value.copy(targetDistanceM=distance,start=start,via=via,lessClimbing=lessClimbing,candidates=emptyList(),selected=null,busy=false,message=null,generationUnavailable=false,completed=false)
    }
    fun search(query: String) {
        val rev=invalidate(); mutable.value=state.value.copy(searchResults=emptyList(),busy=true,message=null)
        job=scope.launch { try {
            val places=services.search(query)
            if(valid(rev)) mutable.value=state.value.copy(searchResults=places,busy=false,message=PlannerMessage.NO_PLACES.takeIf{places.isEmpty()})
        } catch (e: CancellationException) { throw e } catch (e: Exception) { if(valid(rev)) mutable.value=state.value.copy(busy=false,message=PlannerMessage.FAILED) } }
    }
    fun clearSearch() { invalidate(); mutable.value=state.value.copy(searchResults=emptyList(),busy=false) }
    fun locate() {
        val rev=invalidate(); mutable.value=state.value.copy(busy=true,message=null)
        job=scope.launch { try {
            val place=services.currentLocation()
            if(valid(rev)) { mutable.value=state.value.copy(busy=false); if(place!=null) edit(start=place) else mutable.value=state.value.copy(message=PlannerMessage.LOCATION_UNAVAILABLE) }
        } catch(e: CancellationException){throw e} catch(e: Exception){if(valid(rev))mutable.value=state.value.copy(busy=false,message=PlannerMessage.LOCATION_UNAVAILABLE)} }
    }
    fun generate() {
        val value=state.value; val distance=value.targetDistanceM
        if(distance==null || !distance.isFinite() || distance !in 1000.0..50000.0) { mutable.value=value.copy(message=PlannerMessage.INVALID_DISTANCE); return }
        val start=value.start ?: return
        val rev=invalidate(); mutable.value=value.copy(busy=true,selected=null,candidates=emptyList(),message=null,completed=false)
        val request=PlannerRequest(start.coordinate,value.via?.coordinate,distance,value.activity,value.lessClimbing,seed.also{seed=(seed+1)%1000001})
        job=scope.launch { try {
            val result=services.candidates(accountId,request) { existing -> if(valid(rev)) mutable.value=state.value.copy(candidates=existing.take(3)) }
            if(valid(rev)) { mutable.value=state.value.copy(busy=false,candidates=if(state.value.selected!=null)state.value.candidates else result.candidates.take(3),generationUnavailable=result.generationUnavailable,completed=true); services.event(if(result.candidates.isEmpty()) "empty" else "success",value.activity) }
        } catch(e: CancellationException){throw e} catch(e: Exception){if(valid(rev)){mutable.value=state.value.copy(busy=false,message=PlannerMessage.FAILED);services.event("failure",value.activity)}} }
    }
    fun select(candidate: PlannerCandidate?) {
        if(state.value.accepting) { invalidate();mutable.value=state.value.copy(selected=candidate,busy=false,accepting=false) }
        else mutable.value=state.value.copy(selected=candidate)
    }
    fun consumeMessage() { mutable.value=state.value.copy(message=null) }
    fun accept(callback: (AcceptedPlannerRoute)->Unit) {
        val candidate=state.value.selected ?: return
        val rev=invalidate(); mutable.value=state.value.copy(busy=true,accepting=true)
        job=scope.launch { try {
            check(accountCurrent())
            val accepted=services.accept(accountId,candidate)
            if(valid(rev)){ mutable.value=state.value.copy(busy=false,accepting=false);services.event("accepted",candidate.activity,candidate.source);callback(accepted) }
        } catch(e: CancellationException){throw e} catch(e: Exception){if(valid(rev))mutable.value=state.value.copy(busy=false,accepting=false,message=PlannerMessage.SAVE_FAILED)} }
    }
    fun close() { invalidate() }
    fun cancel() { invalidate();services.event("cancelled",state.value.activity) }
}
