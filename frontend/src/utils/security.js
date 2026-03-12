import DOMPurify from 'dompurify';

// Sanitize HTML content to prevent XSS
export const sanitizeHTML = (content) => {
  return DOMPurify.sanitize(content, {
    ALLOWED_TAGS: ['p', 'br', 'strong', 'em', 'u', 'h1', 'h2', 'h3'],
    ALLOWED_ATTR: []
  });
};

// Validate URL to prevent malicious links
export const validateURL = (url) => {
  try {
    const urlObj = new URL(url);
    return ['http:', 'https:'].includes(urlObj.protocol);
  } catch {
    return false;
  }
};

// Sanitize form input
export const sanitizeInput = (input) => {
  return input.trim().replace(/[<>"']/g, '');
};

// Rate limiting helper
export const createRateLimiter = (maxRequests = 5, windowMs = 60000) => {
  const requests = new Map();
  
  return (key = 'default') => {
    const now = Date.now();
    const windowStart = now - windowMs;
    
    if (!requests.has(key)) {
      requests.set(key, []);
    }
    
    const userRequests = requests.get(key).filter(time => time > windowStart);
    
    if (userRequests.length >= maxRequests) {
      return false;
    }
    
    userRequests.push(now);
    requests.set(key, userRequests);
    return true;
  };
};
