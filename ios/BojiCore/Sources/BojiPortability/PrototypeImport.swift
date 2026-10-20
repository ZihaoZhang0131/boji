import Foundation
import BojiDomain
import BojiPersistence

public struct PrototypeOptions: Sendable {
    public var timeZoneIdentifier: String
    public var undatedProfileDay: LocalDay
    public var confirmedUnitsAndProvenance = false
    public var confirmedAmbiguousHistory = false
    public init(timeZoneIdentifier:String,undatedProfileDay:LocalDay) {
        self.timeZoneIdentifier = timeZoneIdentifier;self.undatedProfileDay = undatedProfileDay
    }
}
public struct PrototypePreview: Sendable {
    public let meals:Int
    public let workouts:Int
    public let excludedDemo:Int
    public let needsHistoryConfirmation:Bool
    public let notices:[String]
}
public struct PrototypeConversion: Sendable {
    public let package:ValidatedPackage
    public let preview:PrototypePreview
}
/// Version 1 is a known allowlist of the repository's app.js / energy.js export, never executable JSON.
public actor PrototypeImporter {
    public static let namespace = ImportPlanner.stableID("boji.prototype.schema-1")
    public init() {}
    public func readSelection(_ url:URL) throws -> Data {
        let access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError:NSError?, result:Result<Data,Error>?
        NSFileCoordinator().coordinate(readingItemAt:url,options:[],error:&coordinationError) { location in
            result=Result { try PackageFiles(root:location.deletingLastPathComponent()).read(location.lastPathComponent,maxBytes:PackageLimits.jsonBytes) }
        }
        if let coordinationError { throw coordinationError };guard let result else { throw PackageError.incomplete("原型文件尚未下载") };return try result.get()
    }
    public func inspect(_ data:Data) throws -> PrototypePreview { try Self.preview(Self.decode(data)) }
    public func convert(_ data:Data,options:PrototypeOptions,to parent:URL) throws -> PrototypeConversion {
        let raw=try Self.decode(data),preview=Self.preview(raw)
        guard options.confirmedUnitsAndProvenance, let zone=TimeZone(identifier:options.timeZoneIdentifier) else { throw PackageError.invalid("请确认原始时区、kg／cm／分钟／kcal 单位及未标记内容的真实来源") }
        guard !preview.needsHistoryConfirmation || options.confirmedAmbiguousHistory else { throw PackageError.invalid("请确认缺少身份或提交时间的历史映射") }
        let id=UUID(),working=parent.appendingPathComponent(".prototype-"+id.uuidString),stage=working.appendingPathComponent("package.boji"),media=MediaVault(root:working.appendingPathComponent("photos"))
        let final=parent.appendingPathComponent(id.uuidString+".boji")
        try FileManager.default.createDirectory(at:stage.appendingPathComponent("media"),withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:working) }
        var state=DatasetSnapshot(dataset:Dataset(id:Self.namespace)),notices=preview.notices
        func stable(_ kind:String,_ key:String)->UUID { ImportPlanner.stableID("prototype-v1/"+kind+"/"+key) }
        func timestamp(_ text:String?) throws -> Date {
            guard let text else { return Date(timeIntervalSince1970:0) }
            let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            guard let date=formatter.date(from:text) ?? ISO8601DateFormatter().date(from:text) else { throw PackageError.invalid("原型时间格式") };return date
        }
        func recordTime(_ date:String,_ time:String?) throws -> RecordTime {
            let day=try Self.day(date),clock=PrototypeClock(now:Date(timeIntervalSince1970:0),timeZone:zone)
            var result=RecordTime(clock:clock,selectedDay:day)
            guard let time else { throw PackageError.invalid("原型记录缺少时间，请在原型补齐后导出") }
            let parts=time.split(separator:":");guard parts.count==2,let hour=Int(parts[0]),let minute=Int(parts[1]),(0...23).contains(hour),(0...59).contains(minute) else { throw PackageError.invalid("原型记录时间") }
            result.hour=hour;result.minute=minute;result.instant=nil
            return result
        }
        var profileKeys:Set<String>=[],occurrences:[String:Int]=[:]
        var profiles=raw.profileHistory ?? []
        if let current=raw.profile, !profiles.contains(where:{$0.sameBody(as:current)}) { profiles.append(current) }
        for (index,value) in profiles.enumerated() where value.demo != true {
            guard let sex=value.sex.flatMap(FormulaSex.init(rawValue:)),let age=value.age,let height=value.height,let weight=value.weight,let activity=value.activity else { notices.append("身体资料缺少必要参数，保持未知，未创建不完整的身体资料版本。");continue }
            let day=try value.effectiveDate.map(Self.day) ?? options.undatedProfileDay
            let base=value.id ?? "\(day)/\(value.updatedAt ?? "unknown-submission")"
            let occurrence=occurrences[base,default:0];occurrences[base]=occurrence+1
            let key=base+(occurrence>0 ? "/confirmed-order-\(occurrence)" : "")
            guard profileKeys.insert(key).inserted else { throw PackageError.invalid("重复原型资料身份") }
            let body=BodyProfile(sex:sex,age:age,heightCM:height,weightKG:weight,activityFactor:activity,targetKcal:value.target)
            try EnergyRules.validate(body)
            state.profiles.append(ProfileVersion(id:stable("profile",key),effectiveDay:day,sequence:Int64(index+1),profile:body,createdAt:try timestamp(value.updatedAt)))
        }
        var goals=raw.planHistory ?? []
        if let current=raw.plan, !goals.contains(where:{$0 == current}) { goals.append(current) }
        var goalKeys:Set<String>=[]
        for (index,value) in goals.enumerated() where value.demo != true {
            guard let goal=Goal.allCases.first(where:{$0.title==value.goal}) else { throw PackageError.invalid("原型阶段目标") }
            let key=value.id ?? value.start+"/"+value.goal
            guard goalKeys.insert(key).inserted else { throw PackageError.invalid("同一开始日与目标存在多个阶段，请先在原型整理后导出") }
            var result=GoalStage(id:stable("goal",key),startDay:try Self.day(value.start),goal:goal,sequence:Int64(index+1))
            result.endDay=try value.end.map(Self.day);result.note=value.note ?? "";state.goals.append(result)
        }
        func estimates(_ energy:LegacyEnergy?,meal:inout Meal) throws {
            guard let energy else { return }
            var previous:UUID?
            func append(_ value:LegacyEnergy,_ key:String) throws -> UUID? {
                guard let kcal=value.kcal else { return nil }
                let source:EstimateSource=value.source=="manual" ? .manual : .demo
                let items=try (value.items?.isEmpty==false ? value.items! : [LegacyFood(name:"整餐",grams:nil,kcal:kcal)]).enumerated().map { index,item in
                    guard let name=item.name,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,let kcal=item.kcal else { throw PackageError.invalid("原型食物项") }
                    return FoodItem(id:stable("food","\(meal.id)/\(key)/\(index)"),name:name,grams:item.grams,kcal:kcal)
                }
                // Identity follows content, not the file's changing export timestamp.
                let digest=PackageHash.sha256(try PackageCodec.encode(value))
                var result=EstimateRevision(id:stable("estimate","\(meal.id)/\(key)/\(digest)"),recordID:meal.id,inputRevision:meal.inputRevision,source:source,items:items,totalKcal:kcal,createdAt:try timestamp(value.updatedAt))
                result.previousRevisionID=previous;result.model=value.model;result.provider="原型 v1";result.promptVersion=value.version
                if let low=value.low,let high=value.high { result.range=EstimateRange(low:low,high:high) }
                if source == .demo { result.questions=["原型演示或未核实来源，不计入真实摄入。"] }
                try FoodEstimateRules.validate(result);state.estimates.append(result);return result.id
            }
            if let original=energy.originalEstimate { previous=try append(original.value,"original") }
            let current=try append(energy,"current")
            if energy.source=="manual",energy.status=="manual" { meal.currentEstimateID=current;meal.manualRevision=1 }
            else if current != nil { notices.append("餐食 \(meal.time.localDay) 的示例或过期估算仅保留为历史，当前热量未知。") }
        }
        var knownMeals:Set<String>=[],excludedDays:Set<LocalDay>=[]
        for value in raw.meals {
            guard knownMeals.insert(value.id).inserted else { throw PackageError.invalid("原型餐食标识重复") }
            if value.demo==true { excludedDays.insert(try Self.day(value.date));continue }
            var meal=Meal(id:stable("meal",value.id),time:try recordTime(value.date,value.time))
            meal.note=value.note?.isEmpty==false ? value.note! : (value.title ?? "");meal.slot=value.slot;meal.tags=value.tags ?? []
            guard (value.photos ?? []).count<=9 else { throw PackageError.limit("每餐九张图") }
            for (index,text) in (value.photos ?? []).enumerated() {
                guard let comma=text.firstIndex(of:","),["data:image/jpeg;base64","data:image/png;base64","data:image/heic;base64","data:image/heif;base64"].contains(String(text[..<comma])),
                      text.utf8.count<=PackageLimits.imageBytes*4/3+128,let bytes=Data(base64Encoded:String(text[text.index(after:comma)...])) else { throw PackageError.incomplete("照片不是嵌入式图片。请保持原型服务运行并重新完整导出，不能使用 assets 路径或远程地址。") }
                var asset=try media.ingest(bytes);asset.id=stable("photo","\(value.id)/\(index)/\(asset.sha256)")
                state.photos.append(asset);meal.photoIDs.append(asset.id)
            }
            try estimates(value.energy,meal:&meal);try MealRules.validate(meal);state.meals.append(meal)
        }
        func workout(_ value:LegacyWorkout,draft:Bool) throws -> Workout {
            var result=Workout(id:stable("workout",value.id),time:try recordTime(value.date,value.time));result.name=value.name ?? ""
            result.exercises=try value.exercises.enumerated().map { index,item in
                guard item.type=="body" || item.type=="weight" else { throw PackageError.invalid("原型动作类型") }
                return Exercise(id:stable("exercise","\(value.id)/\(item.id ?? String(index))"),name:item.name,kind:item.type=="body" ? .bodyweight : .weighted,weightConvention:item.unit ?? "总重量（kg，迁移时已确认）",sets:item.sets.enumerated().compactMap { setIndex,set in
                    if !draft && set.done != true { return nil }
                    return WorkoutSet(id:stable("set","\(value.id)/\(index)/\(set.id ?? String(setIndex))"),weightKG:item.type=="body" ? nil : set.weight,reps:set.reps,completed:set.done==true)
                })
            }.filter { draft || !$0.sets.isEmpty }
            if !draft,let energy=value.energy,let intensity=TrainingIntensity.allCases.first(where:{$0.met==energy.met}),let kcal=energy.activeKcal {
                var snapshot=WorkoutEnergy(weightKG:energy.weight,minutes:energy.minutes,intensity:intensity,profileVersionID:nil,kcal:kcal,algorithmVersion:"prototype-v1/"+(energy.method ?? "unknown"),createdAt:Date(timeIntervalSince1970:0))
                snapshot.id=stable("energy",value.id+"/"+PackageHash.sha256(try PackageCodec.encode(energy)))
                result.energyHistory=[snapshot];result.currentEnergyID=snapshot.id
            } else if !draft, value.energy != nil { notices.append("训练 \(value.date) 的计算参数不全，消耗保持未知；未按当前体重补算。") }
            return result
        }
        var knownWorkouts:Set<String>=[]
        for value in raw.workouts {
            guard knownWorkouts.insert(value.id).inserted else { throw PackageError.invalid("原型训练标识重复") }
            if value.isKnownDemo { excludedDays.insert(try Self.day(value.date));continue }
            let result=try workout(value,draft:false)
            if result.exercises.isEmpty { notices.append("训练 \(value.date) 没有完成组，未计入正式训练。");excludedDays.insert(result.time.localDay);continue }
            state.workouts.append(result)
        }
        if let value=raw.draft, !value.isKnownDemo {
            guard !knownWorkouts.contains(value.id) else { throw PackageError.invalid("原型活动草稿与正式训练共用身份，需先整理") }
            let result=try workout(value,draft:true)
            var draft=RecordDraft(id:stable("draft",value.id),content:.workout(result),savedAt:Date(timeIntervalSince1970:0))
            var fields=WorkoutDraftFields();fields.minutesText=value.duration.map { NSDecimalNumber(decimal:$0).stringValue } ?? ""
            if let met=value.met,let intensity=TrainingIntensity.allCases.first(where:{$0.met==met}) { fields.intensity=intensity }
            draft.workoutFields=fields;state.drafts=[draft]
        }
        for day in Set(try (raw.complete ?? []).map(Self.day)).sorted() {
            if state.activeMeals.contains(where:{$0.time.localDay==day}) && !excludedDays.contains(day) { state.confirmations.append(DayConfirmation(day:day,confirmedAt:Date(timeIntervalSince1970:0),factsRevision:0)) }
            else { notices.append("\(day) 排除示例或未完成组后不再沿用已记全确认。") }
        }
        try PackageValidation.validate(state)
        let contents=try PackageContents(snapshot:state),writer=LocalFileAccess()
        var files:[PackageFile]=[]
        func write(_ data:Data,_ path:String) throws { try writer.writeAtomically(data,to:stage.appendingPathComponent(path));files.append(PackageFile(path:path,byteCount:data.count,sha256:PackageHash.sha256(data))) }
        for (path,data) in try contents.dataFiles() { try write(data,path) }
        var paths:Set<String>=[]
        for asset in state.photos where paths.insert(asset.relativePath).inserted { try write(media.read(asset),asset.relativePath) }
        let manifest=PackageManifest(datasetID:state.dataset.id,exportID:id,createdAt:Date(),revision:0,counts:contents.counts,files:files.sorted {$0.path<$1.path})
        try writer.writeAtomically(PackageCodec.encode(manifest),to:stage.appendingPathComponent("manifest.json"))
        _ = try PackageReader().read(stage)
        try FileManager.default.moveItem(at:stage,to:final)
        return PrototypeConversion(package:try PackageReader().read(final),preview:PrototypePreview(meals:state.meals.count,workouts:state.workouts.count,excludedDemo:preview.excludedDemo,needsHistoryConfirmation:preview.needsHistoryConfirmation,notices:Array(Set(notices)).sorted()))
    }
    private static func day(_ text:String) throws -> LocalDay {
        let values=text.split(separator:"-");guard values.count==3,let year=Int(values[0]),let month=Int(values[1]),let day=Int(values[2]) else { throw PackageError.invalid("原型日期") };return try LocalDay(year:year,month:month,day:day)
    }
    private static func decode(_ data:Data) throws -> LegacyRoot {
        guard data.count<=PackageLimits.jsonBytes else { throw PackageError.limit("原型 JSON 128 MiB") }
        let raw=try JSONDecoder().decode(LegacyRoot.self,from:data)
        guard raw.schema_version==1,raw.prototype else { throw PackageError.invalid("仅支持明确标记的原型版本 1") }
        let count=raw.meals.count+raw.workouts.count+(raw.profileHistory?.count ?? 0)+(raw.planHistory?.count ?? 0)
        guard count<=PackageLimits.records,raw.meals.reduce(0,{$0+($1.photos?.count ?? 0)})<=PackageLimits.photos else { throw PackageError.limit("原型记录数量") }
        return raw
    }
    private static func preview(_ raw:LegacyRoot) -> PrototypePreview {
        let profiles=(raw.profileHistory ?? []) + (raw.profile.map {[$0]} ?? [])
        let missing=profiles.contains { $0.demo != true && ($0.effectiveDate==nil || ($0.id==nil && $0.updatedAt==nil)) }
        return PrototypePreview(meals:raw.meals.filter{$0.demo != true}.count,workouts:raw.workouts.filter{!$0.isKnownDemo}.count,excludedDemo:raw.meals.filter{$0.demo==true}.count+raw.workouts.filter(\.isKnownDemo).count+profiles.filter{$0.demo==true}.count,needsHistoryConfirmation:missing,notices:["原型没有可靠时区和统一单位标记，请按记录时实际环境确认。","缺少提交时间用 1970-01-01 UTC 表示未知；记录的绝对时刻保持空值。","无 ID 的资料按生效日和原提交时间映射；仍有重复时按确认过的原始顺序区分。","已知演示训练（虚构样例标记）与 demo:true 默认排除；未核实估算只保留演示历史。"])
    }
}
private struct PrototypeClock:AppClock { let now:Date;let timeZone:TimeZone }
private struct LegacyRoot:Decodable {
    let schema_version:Int;let prototype:Bool;let meals:[LegacyMeal];let workouts:[LegacyWorkout]
    let profile:LegacyProfile?;let profileHistory:[LegacyProfile]?;let plan:LegacyGoal?;let planHistory:[LegacyGoal]?;let complete:[String]?;let draft:LegacyWorkout?
}
private struct LegacyMeal:Decodable {
    let id:String;let date:String;let time:String?;let note:String?;let title:String?;let slot:String?;let tags:[String]?;let photos:[String]?;let demo:Bool?;let energy:LegacyEnergy?
}
private struct LegacyFood:Codable { let name:String?;let grams:Decimal?;let kcal:Decimal? }
private struct LegacyEnergy:Codable {
    let status:String?;let source:String?;let kcal:Decimal?;let items:[LegacyFood]?;let low:Decimal?;let high:Decimal?;let model:String?;let version:String?;let updatedAt:String?;let originalEstimate:LegacyEnergyBox?
}
private final class LegacyEnergyBox:Codable { let value:LegacyEnergy
    init(from decoder:any Decoder) throws { value=try LegacyEnergy(from:decoder) }
    func encode(to encoder:any Encoder) throws { try value.encode(to:encoder) }
}
private struct LegacyWorkout:Decodable {
    let id:String;let date:String;let time:String?;let name:String?;let exercises:[LegacyExercise];let duration:Decimal?;let met:Decimal?;let energy:LegacyWorkoutEnergy?;let demo:Bool?;let sourceNote:String?
    var isKnownDemo:Bool { demo==true || (["w1003","w1006","w1009"].contains(id) && sourceNote?.contains("虚构样例")==true) }
}
private struct LegacyExercise:Decodable { let id:String?;let name:String;let type:String;let unit:String?;let sets:[LegacySet] }
private struct LegacySet:Decodable { let id:String?;let weight:Decimal?;let reps:Int?;let done:Bool? }
private struct LegacyWorkoutEnergy:Codable { let activeKcal:Int?;let weight:Decimal?;let minutes:Decimal?;let met:Decimal?;let method:String?;let version:String? }
private struct LegacyProfile:Decodable {
    let id:String?;let sex:String?;let age:Int?;let height:Decimal?;let weight:Decimal?;let activity:Decimal?;let target:Decimal?;let demo:Bool?;let effectiveDate:String?;let updatedAt:String?
    func sameBody(as other:Self)->Bool { sex==other.sex && age==other.age && height==other.height && weight==other.weight && activity==other.activity && target==other.target && demo==other.demo }
}
private struct LegacyGoal:Decodable,Equatable { let id:String?;let goal:String;let start:String;let end:String?;let note:String?;let demo:Bool? }
