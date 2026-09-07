package run.plainstride.feature.community

import kotlin.math.*

data class GuidancePoint(val latitude:Double,val longitude:Double,val altitudeM:Double?=null)
data class GuidanceFix(val point:GuidancePoint,val accuracyM:Double,val courseDegrees:Double?=null)
enum class GuidanceSignal { ACQUIRING,ON_ROUTE,DEVIATED,REJOINED,WRONG_WAY,ARRIVED }
data class GuidanceState(val signal:GuidanceSignal,val progress:Double,val remainingM:Double,val nearestDistanceM:Double,val rejoinPoint:GuidancePoint?=null)

/** Course-aware exact-polyline guidance; never invents maneuvers, street names, or reroutes. */
class RouteGuidanceEngine(points:List<GuidancePoint>,reverse:Boolean=false){
 private val route=simplify(if(reverse)points.reversed() else points,2.5).also{require(it.size in 2..50_000)}
 private val cumulative=DoubleArray(route.size).also{out->for(i in 1 until route.size)out[i]=out[i-1]+distance(route[i-1],route[i])}
 private val total=cumulative.last().coerceAtLeast(1.0);private val index=SegmentIndex(route)
 private var acquired=false;private var prior=0.0;private var deviations=0;private var onRoute=0;private var wrongWay=0;private var wasOffRoute=false;private var arrived=false
 fun update(fix:GuidanceFix):GuidanceState{
  if(arrived)return state(GuidanceSignal.ARRIVED,1.0,0.0,distance(fix.point,route.last()))
  val match=index.nearest(fix.point,fix.accuracyM);val raw=(cumulative[match.segment]+match.fraction*distance(route[match.segment],route[match.segment+1]))/total
  if(!acquired){acquired=match.distanceM<=max(45.0,fix.accuracyM*2)&&raw<=.12;if(!acquired)return state(GuidanceSignal.ACQUIRING,0.0,total,match.distanceM,match.point)}
  val threshold=max(35.0,fix.accuracyM.coerceAtLeast(0.0)*1.5)
  if(match.distanceM>threshold){deviations++;onRoute=0}else{onRoute++;deviations=0};if(deviations>=3)wasOffRoute=true
  val delta=fix.courseDegrees?.takeIf{match.distanceM<=threshold}?.let{angularDifference(it,bearing(route[match.segment],route[match.segment+1]))}
  wrongWay=if(delta!=null&&delta>120)wrongWay+1 else 0
  val bounded=raw.coerceIn((prior-.015).coerceAtLeast(0.0),(prior+.12).coerceAtMost(1.0));prior=max(prior,bounded)
  arrived=prior>=.92&&distance(fix.point,route.last())<=threshold;val rejoined=wasOffRoute&&onRoute>=3;if(rejoined)wasOffRoute=false
  val signal=when{arrived->GuidanceSignal.ARRIVED;deviations>=3->GuidanceSignal.DEVIATED;wrongWay>=3->GuidanceSignal.WRONG_WAY;rejoined->GuidanceSignal.REJOINED;else->GuidanceSignal.ON_ROUTE}
  return state(signal,prior,(total*(1-prior)).coerceAtLeast(0.0),match.distanceM,match.point)
 }
 private fun state(signal:GuidanceSignal,progress:Double,remaining:Double,nearest:Double,rejoin:GuidancePoint?=null)=GuidanceState(signal,progress,remaining,nearest,rejoin)
}

private data class Match(val segment:Int,val fraction:Double,val point:GuidancePoint,val distanceM:Double)
private class SegmentIndex(private val points:List<GuidancePoint>){
 private val size=.002;private val cells=mutableMapOf<Long,MutableList<Int>>()
 init{for(i in 0 until points.lastIndex){val a=cell(points[i]);val b=cell(points[i+1]);for(x in min(a.first,b.first)..max(a.first,b.first))for(y in min(a.second,b.second)..max(a.second,b.second))cells.getOrPut(key(x,y)){mutableListOf()}.add(i)}}
 fun nearest(point:GuidancePoint,accuracyM:Double):Match{val c=cell(point);val radius=max(1,ceil(max(accuracyM,75.0)/180).toInt());val candidates=buildSet{for(x in c.first-radius..c.first+radius)for(y in c.second-radius..c.second+radius)addAll(cells[key(x,y)].orEmpty())}.ifEmpty{(0 until points.lastIndex).toSet()};return candidates.asSequence().map{projected(point,points[it],points[it+1],it)}.minBy{it.distanceM}}
 private fun cell(p:GuidancePoint)=floor(p.latitude/size).toInt() to floor(p.longitude/size).toInt();private fun key(x:Int,y:Int)=(x.toLong() shl 32) xor (y.toLong() and 0xffffffffL)
}
private fun projected(p:GuidancePoint,a:GuidancePoint,b:GuidancePoint,segment:Int):Match{val ys=111_320.0;val xs=ys*cos(Math.toRadians(p.latitude));val ax=(a.longitude-p.longitude)*xs;val ay=(a.latitude-p.latitude)*ys;val dx=(b.longitude-a.longitude)*xs;val dy=(b.latitude-a.latitude)*ys;val t=if(dx*dx+dy*dy==0.0)0.0 else (-(ax*dx+ay*dy)/(dx*dx+dy*dy)).coerceIn(0.0,1.0);val q=GuidancePoint(a.latitude+(b.latitude-a.latitude)*t,a.longitude+(b.longitude-a.longitude)*t,a.altitudeM);return Match(segment,t,q,hypot(ax+dx*t,ay+dy*t))}
fun simplify(points:List<GuidancePoint>,toleranceM:Double):List<GuidancePoint>{if(points.size<3||toleranceM<=0)return points;val keep=BooleanArray(points.size).also{it[0]=true;it[it.lastIndex]=true};fun visit(start:Int,end:Int){var best=0.0;var index=-1;for(i in start+1 until end){val d=projected(points[i],points[start],points[end],start).distanceM;if(d>best){best=d;index=i}};if(index>=0&&best>toleranceM){keep[index]=true;visit(start,index);visit(index,end)}};visit(0,points.lastIndex);return points.filterIndexed{i,_->keep[i]}}
private fun distance(a:GuidancePoint,b:GuidancePoint):Double{val p1=Math.toRadians(a.latitude);val p2=Math.toRadians(b.latitude);val dp=p2-p1;val dl=Math.toRadians(b.longitude-a.longitude);val h=sin(dp/2).pow(2)+cos(p1)*cos(p2)*sin(dl/2).pow(2);return 6371000*2*atan2(sqrt(h),sqrt(1-h))}
private fun bearing(a:GuidancePoint,b:GuidancePoint):Double{val dl=Math.toRadians(b.longitude-a.longitude);val p1=Math.toRadians(a.latitude);val p2=Math.toRadians(b.latitude);return(Math.toDegrees(atan2(sin(dl)*cos(p2),cos(p1)*sin(p2)-sin(p1)*cos(p2)*cos(dl)))+360)%360}
private fun angularDifference(a:Double,b:Double)=abs((a-b+540)%360-180)

object OfflineRouteExporter{
 fun gpx(name:String,points:List<GuidancePoint>):ByteArray{require(points.size>=2);val escaped=name.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;");return buildString{append("<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"Plainstride\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>");append(escaped);append("</name><trkseg>");points.forEach{append("<trkpt lat=\"").append(it.latitude).append("\" lon=\"").append(it.longitude).append("\">");it.altitudeM?.let{e->append("<ele>").append(e).append("</ele>")};append("</trkpt>")};append("</trkseg></trk></gpx>")}.encodeToByteArray()}
}
