#!/bin/bash
# News Briefing Workflow - Tech/AI Edition

set -e

PAYLOAD_TYPE="${1:-tech}"

if [ "$PAYLOAD_TYPE" == "tech" ] || [ "$PAYLOAD_TYPE" == "all" ]; then
    echo "=== TECH/AI NEWS BRIEFING ==="
    echo ""
    
    # 1. Brave Search - Broad news sweep
    echo "🔍 Running Brave search for tech/AI news..."
    
    # 2. Agent Browser - Targeted site scraping
    echo "🌐 Scraping key tech sites..."
    
    # TechCrunch
    echo "  - TechCrunch..."
    agent-browser open https://techcrunch.com/latest/ --session tech-news 2>/dev/null || true
    sleep 2
    
    # The Verge
    echo "  - The Verge..."
    agent-browser open https://www.theverge.com/tech --session tech-news 2>/dev/null || true
    sleep 2
    
    # Ars Technica  
    echo "  - Ars Technica..."
    agent-browser open https://arstechnica.com/ --session tech-news 2>/dev/null || true
    sleep 2
    
    # Wired
    echo "  - Wired..."
    agent-browser open https://www.wired.com/ --session tech-news 2>/dev/null || true
    
    echo ""
    echo "✅ Tech briefing sources loaded"
fi

if [ "$PAYLOAD_TYPE" == "insurance" ] || [ "$PAYLOAD_TYPE" == "all" ]; then
    echo "=== INSURANCE INDUSTRY NEWS BRIEFING ==="
    echo ""
    
    # 1. Brave Search - Industry news sweep
    echo "🔍 Running Brave search for insurance industry news..."
    
    # 2. Agent Browser - Targeted site scraping
    echo "🌐 Scraping key insurance sites..."
    
    # InsuranceNewsNet
    echo "  - InsuranceNewsNet..."
    agent-browser open https://insurancenewsnet.com/ --session insurance-news 2>/dev/null || true
    sleep 2
    
    # Insurance Journal
    echo "  - Insurance Journal..."
    agent-browser open https://www.insurancejournal.com/ --session insurance-news 2>/dev/null || true
    sleep 2
    
    # ThinkAdvisor
    echo "  - ThinkAdvisor..."
    agent-browser open https://www.thinkadvisor.com/ --session insurance-news 2>/dev/null || true
    sleep 2
    
    # LifeHealthPro
    echo "  - LifeHealthPro..."
    agent-browser open https://www.lifehealthpro.com/ --session insurance-news 2>/dev/null || true
    
    echo ""
    echo "✅ Insurance briefing sources loaded"
fi

# Cleanup
agent-browser --session tech-news close 2>/dev/null || true
agent-browser --session insurance-news close 2>/dev/null || true

echo ""
echo "📝 Ready for analysis"
