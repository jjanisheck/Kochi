import Foundation
import os.log

// MARK: - Performance Monitor
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var diskUsage: Double = 0
    @Published var fps: Double = 60
    @Published var networkLatency: Double = 0
    
    private let logger = Logger(subsystem: "com.kochi.app", category: "Performance")
    private var frameCount = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var performanceTimer: Timer?
    
    // Metrics storage
    private var metrics: [PerformanceMetric] = []
    private let metricsQueue = DispatchQueue(label: "com.kochi.performance.metrics")
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Monitoring Control
    func startMonitoring() {
        // CPU and Memory monitoring
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateSystemMetrics()
        }
        
        logger.info("Performance monitoring started")
    }
    
    func stopMonitoring() {
        performanceTimer?.invalidate()
        performanceTimer = nil

        logger.info("Performance monitoring stopped")
    }
    
    // MARK: - System Metrics
    private func updateSystemMetrics() {
        cpuUsage = getCurrentCPUUsage()
        memoryUsage = getCurrentMemoryUsage()
        diskUsage = getCurrentDiskUsage()
        
        // Log metrics
        let metric = PerformanceMetric(
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            diskUsage: diskUsage,
            fps: fps,
            networkLatency: networkLatency
        )
        
        metricsQueue.async { [weak self] in
            self?.metrics.append(metric)
            // Keep only last 1000 metrics
            if self?.metrics.count ?? 0 > 1000 {
                self?.metrics.removeFirst()
            }
        }
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / Double(1024 * 1024) // Convert to MB
        }
        return 0
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size)
            let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
            return (usedMemory / totalMemory) * 100
        }
        return 0
    }
    
    private func getCurrentDiskUsage() -> Double {
        do {
            let documentDirectory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            
            let values = try documentDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            
            if let available = values.volumeAvailableCapacity,
               let total = values.volumeTotalCapacity {
                let used = total - available
                return (Double(used) / Double(total)) * 100
            }
        } catch {
            logger.error("Failed to get disk usage: \(error.localizedDescription)")
        }
        return 0
    }
    
    // MARK: - Performance Analysis
    func analyzePerformance() -> PerformanceReport {
        var report = PerformanceReport()
        
        metricsQueue.sync {
            guard !metrics.isEmpty else { return }
            
            // Calculate averages
            let totalCPU = metrics.reduce(0) { $0 + $1.cpuUsage }
            let totalMemory = metrics.reduce(0) { $0 + $1.memoryUsage }
            let totalFPS = metrics.reduce(0) { $0 + $1.fps }
            
            let count = Double(metrics.count)
            report.averageCPU = totalCPU / count
            report.averageMemory = totalMemory / count
            report.averageFPS = totalFPS / count
            
            // Find peaks
            report.peakCPU = metrics.max(by: { $0.cpuUsage < $1.cpuUsage })?.cpuUsage ?? 0
            report.peakMemory = metrics.max(by: { $0.memoryUsage < $1.memoryUsage })?.memoryUsage ?? 0
            report.minFPS = metrics.min(by: { $0.fps < $1.fps })?.fps ?? 60
            
            // Identify bottlenecks
            report.bottlenecks = identifyBottlenecks()
        }
        
        return report
    }
    
    private func identifyBottlenecks() -> [PerformanceBottleneck] {
        var bottlenecks: [PerformanceBottleneck] = []
        
        if cpuUsage > 80 {
            bottlenecks.append(PerformanceBottleneck(
                type: .cpu,
                severity: .high,
                description: "High CPU usage detected",
                recommendation: "Consider optimizing algorithms or reducing concurrent operations"
            ))
        }
        
        if memoryUsage > 80 {
            bottlenecks.append(PerformanceBottleneck(
                type: .memory,
                severity: .high,
                description: "High memory usage detected",
                recommendation: "Review memory allocations and implement caching strategies"
            ))
        }
        
        if fps < 30 {
            bottlenecks.append(PerformanceBottleneck(
                type: .rendering,
                severity: .medium,
                description: "Low frame rate detected",
                recommendation: "Optimize UI rendering and reduce complex animations"
            ))
        }
        
        return bottlenecks
    }
    
    // MARK: - Optimization Suggestions
    func getOptimizationSuggestions() -> [OptimizationSuggestion] {
        var suggestions: [OptimizationSuggestion] = []
        
        // Analyze recent metrics
        let recentMetrics = metrics.suffix(50)
        
        // Memory optimization
        if recentMetrics.contains(where: { $0.memoryUsage > 70 }) {
            suggestions.append(OptimizationSuggestion(
                category: .memory,
                title: "Implement Memory Caching",
                description: "Use NSCache for frequently accessed data",
                estimatedImprovement: "20-30% memory reduction",
                priority: .high
            ))
        }
        
        // CPU optimization
        if recentMetrics.contains(where: { $0.cpuUsage > 60 }) {
            suggestions.append(OptimizationSuggestion(
                category: .cpu,
                title: "Use Background Queues",
                description: "Move heavy computations to background threads",
                estimatedImprovement: "40-50% UI responsiveness improvement",
                priority: .high
            ))
        }
        
        // Rendering optimization
        if recentMetrics.contains(where: { $0.fps < 50 }) {
            suggestions.append(OptimizationSuggestion(
                category: .rendering,
                title: "Optimize SwiftUI Views",
                description: "Use lazy loading and view recycling",
                estimatedImprovement: "15-25% FPS improvement",
                priority: .medium
            ))
        }
        
        return suggestions
    }
}

// MARK: - Supporting Types
struct PerformanceMetric {
    let timestamp: Date
    let cpuUsage: Double
    let memoryUsage: Double
    let diskUsage: Double
    let fps: Double
    let networkLatency: Double
}

struct PerformanceReport {
    var averageCPU: Double = 0
    var averageMemory: Double = 0
    var averageFPS: Double = 60
    var peakCPU: Double = 0
    var peakMemory: Double = 0
    var minFPS: Double = 60
    var bottlenecks: [PerformanceBottleneck] = []
}

struct PerformanceBottleneck {
    enum BottleneckType {
        case cpu, memory, disk, network, rendering
    }
    
    enum Severity {
        case low, medium, high, critical
    }
    
    let type: BottleneckType
    let severity: Severity
    let description: String
    let recommendation: String
}

struct OptimizationSuggestion {
    enum Category {
        case memory, cpu, rendering, network, storage
    }
    
    enum Priority {
        case low, medium, high
    }
    
    let category: Category
    let title: String
    let description: String
    let estimatedImprovement: String
    let priority: Priority
}

// MARK: - Performance Testing
class PerformanceTest {
    private let name: String
    private let monitor: PerformanceMonitor
    private var startTime: CFAbsoluteTime = 0
    private var startMetrics: PerformanceMetric?
    
    init(name: String, monitor: PerformanceMonitor = .shared) {
        self.name = name
        self.monitor = monitor
    }
    
    func start() {
        startTime = CFAbsoluteTimeGetCurrent()
        startMetrics = PerformanceMetric(
            timestamp: Date(),
            cpuUsage: monitor.cpuUsage,
            memoryUsage: monitor.memoryUsage,
            diskUsage: monitor.diskUsage,
            fps: monitor.fps,
            networkLatency: monitor.networkLatency
        )
    }
    
    func end() -> PerformanceTestResult {
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        let endMetrics = PerformanceMetric(
            timestamp: Date(),
            cpuUsage: monitor.cpuUsage,
            memoryUsage: monitor.memoryUsage,
            diskUsage: monitor.diskUsage,
            fps: monitor.fps,
            networkLatency: monitor.networkLatency
        )
        
        return PerformanceTestResult(
            name: name,
            duration: duration,
            startMetrics: startMetrics!,
            endMetrics: endMetrics
        )
    }
}

struct PerformanceTestResult {
    let name: String
    let duration: CFAbsoluteTime
    let startMetrics: PerformanceMetric
    let endMetrics: PerformanceMetric
    
    var cpuDelta: Double {
        endMetrics.cpuUsage - startMetrics.cpuUsage
    }
    
    var memoryDelta: Double {
        endMetrics.memoryUsage - startMetrics.memoryUsage
    }
    
    var summary: String {
        """Test: \(name)
Duration: \(String(format: "%.3f", duration))s
CPU Delta: \(String(format: "%.1f", cpuDelta))%
Memory Delta: \(String(format: "%.1f", memoryDelta))%
Average FPS: \(String(format: "%.1f", (startMetrics.fps + endMetrics.fps) / 2))
"""
    }
}