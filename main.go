package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
)

const (
	annotationKey = "tcpdump.antrea.io"
	captureDir    = "/tmp"
)

type CaptureManager struct {
	clientset *kubernetes.Clientset
	nodeName  string
	captures  map[string]*exec.Cmd
	mu        sync.Mutex
}

func main() {
	klog.InitFlags(nil)
	
	nodeName := os.Getenv("NODE_NAME")
	if nodeName == "" {
		klog.Fatal("NODE_NAME environment variable not set")
	}

	config, err := rest.InClusterConfig()
	if err != nil {
		klog.Fatalf("Failed to get in-cluster config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		klog.Fatalf("Failed to create clientset: %v", err)
	}

	manager := &CaptureManager{
		clientset: clientset,
		nodeName:  nodeName,
		captures:  make(map[string]*exec.Cmd),
	}

	klog.Infof("Starting packet capture controller on node %s", nodeName)
	manager.run()
}

func (m *CaptureManager) run() {
	for {
		m.watchPods()
		klog.Warning("Watch connection closed, reconnecting in 5s...")
		time.Sleep(5 * time.Second)
	}
}

func (m *CaptureManager) watchPods() {
	ctx := context.Background()
	
	watcher, err := m.clientset.CoreV1().Pods("").Watch(ctx, metav1.ListOptions{
		FieldSelector: fmt.Sprintf("spec.nodeName=%s", m.nodeName),
	})
	if err != nil {
		klog.Errorf("Failed to watch pods: %v", err)
		return
	}
	defer watcher.Stop()

	for event := range watcher.ResultChan() {
		pod, ok := event.Object.(*corev1.Pod)
		if !ok {
			continue
		}

		switch event.Type {
		case watch.Added, watch.Modified:
			m.handlePodUpdate(pod)
		case watch.Deleted:
			m.stopCapture(pod)
		}
	}
}

func (m *CaptureManager) handlePodUpdate(pod *corev1.Pod) {
	podKey := fmt.Sprintf("%s/%s", pod.Namespace, pod.Name)
	
	if pod.Status.Phase != corev1.PodRunning {
		return
	}

	annotationValue, hasAnnotation := pod.Annotations[annotationKey]
	
	m.mu.Lock()
	_, isCapturing := m.captures[podKey]
	m.mu.Unlock()

	if hasAnnotation && !isCapturing {
		m.startCapture(pod, annotationValue)
	} else if !hasAnnotation && isCapturing {
		m.stopCapture(pod)
	}
}

func (m *CaptureManager) startCapture(pod *corev1.Pod, maxFiles string) {
	podKey := fmt.Sprintf("%s/%s", pod.Namespace, pod.Name)
	
	if pod.Status.PodIP == "" {
		klog.Warningf("Pod %s has no IP yet, skipping capture", podKey)
		return
	}

	captureFile := filepath.Join(captureDir, fmt.Sprintf("capture-%s.pcap", pod.Name))
	
	// tcpdump -C 1 means 1MB per file, -W maxFiles means max number of files
	cmd := exec.Command("tcpdump", "-C", "1", "-W", maxFiles, "-w", captureFile, "-i", "any", "-n")
	
	// Capture stderr for debugging
	stderr, err := cmd.StderrPipe()
	if err != nil {
		klog.Errorf("Failed to get stderr pipe for pod %s: %v", podKey, err)
		return
	}
	
	if err := cmd.Start(); err != nil {
		klog.Errorf("Failed to start capture for pod %s: %v", podKey, err)
		return
	}

	// Log stderr in background
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := stderr.Read(buf)
			if n > 0 {
				klog.Infof("tcpdump stderr for %s: %s", podKey, string(buf[:n]))
			}
			if err != nil {
				break
			}
		}
	}()

	m.mu.Lock()
	m.captures[podKey] = cmd
	m.mu.Unlock()

	klog.Infof("Started packet capture for pod %s (max files: %s)", podKey, maxFiles)
}

func (m *CaptureManager) stopCapture(pod *corev1.Pod) {
	podKey := fmt.Sprintf("%s/%s", pod.Namespace, pod.Name)
	
	m.mu.Lock()
	cmd, exists := m.captures[podKey]
	if exists {
		delete(m.captures, podKey)
	}
	m.mu.Unlock()

	if !exists {
		return
	}

	if cmd.Process != nil {
		cmd.Process.Kill()
	}

	capturePattern := filepath.Join(captureDir, fmt.Sprintf("capture-%s.pcap*", pod.Name))
	matches, err := filepath.Glob(capturePattern)
	if err != nil {
		klog.Errorf("Failed to find capture files for pod %s: %v", podKey, err)
		return
	}

	for _, file := range matches {
		if strings.HasPrefix(filepath.Base(file), fmt.Sprintf("capture-%s.pcap", pod.Name)) {
			if err := os.Remove(file); err != nil {
				klog.Errorf("Failed to remove capture file %s: %v", file, err)
			} else {
				klog.Infof("Removed capture file: %s", file)
			}
		}
	}

	klog.Infof("Stopped packet capture for pod %s", podKey)
}
