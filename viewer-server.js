#!/usr/bin/env node
const express = require('express');
const fs = require('fs');
const path = require('path');
const app = express();

const PORT = process.env.PORT || 8090;
const CAPTURED_DIR = process.env.CAPTURED_DIR || '/app/captured';

// Serve static files
app.use(express.static('/app'));

// Root redirect
app.get('/', (req, res) => {
    res.redirect('/viewer');
});

// API endpoint for file list
app.get('/api/files/:directory', (req, res) => {
    const dir = req.params.directory === 'configs' ? '/app/configs' : CAPTURED_DIR;
    
    try {
        const files = fs.readdirSync(dir)
            .filter(f => f.endsWith('.json'))
            .map(f => ({
                name: f,
                path: path.join(dir, f),
                size: fs.statSync(path.join(dir, f)).size
            }));
        res.json(files);
    } catch (error) {
        res.json([]);
    }
});

// API endpoint for file content
app.get('/api/file/:directory/:filename', (req, res) => {
    const dir = req.params.directory === 'configs' ? '/app/configs' : CAPTURED_DIR;
    const filePath = path.join(dir, req.params.filename);
    
    try {
        const content = fs.readFileSync(filePath, 'utf8');
        res.json(JSON.parse(content));
    } catch (error) {
        res.status(404).json({ error: 'File not found' });
    }
});

// Capture status endpoint
app.get('/capture/status', (req, res) => {
    try {
        const files = fs.readdirSync(CAPTURED_DIR)
            .filter(f => f.endsWith('.json'));
        
        let totalRoutes = 0;
        files.forEach(f => {
            try {
                const content = fs.readFileSync(path.join(CAPTURED_DIR, f), 'utf8');
                const data = JSON.parse(content);
                if (data.routes) {
                    totalRoutes += data.routes.length;
                }
            } catch (e) {
                // Skip invalid files
            }
        });
        
        res.json({
            status: 'running',
            captured_routes: totalRoutes,
            files: files.length
        });
    } catch (error) {
        res.json({
            status: 'error',
            captured_routes: 0,
            files: 0
        });
    }
});

// Mock capture/live endpoint - returns latest captures
app.get('/capture/live', (req, res) => {
    try {
        // Find the most recent capture file
        const files = fs.readdirSync(CAPTURED_DIR)
            .filter(f => f.endsWith('.json'))
            .map(f => ({
                name: f,
                path: path.join(CAPTURED_DIR, f),
                mtime: fs.statSync(path.join(CAPTURED_DIR, f)).mtime
            }))
            .sort((a, b) => b.mtime - a.mtime);
        
        if (files.length > 0) {
            const latestFile = files[0];
            const content = fs.readFileSync(latestFile.path, 'utf8');
            const data = JSON.parse(content);
            
            // Return in the format viewer expects
            res.json({
                count: data.routes ? data.routes.length : 0,
                routes: data.routes || [],
                timestamp: latestFile.mtime
            });
        } else {
            res.json({ count: 0, routes: [] });
        }
    } catch (error) {
        res.status(500).json({ error: 'No captures available' });
    }
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', captured_dir: CAPTURED_DIR });
});

// Serve viewer HTML
app.get('/viewer', (req, res) => {
    res.sendFile('/app/viewer.html');
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Viewer server running on port ${PORT}`);
    console.log(`Captured directory: ${CAPTURED_DIR}`);
});