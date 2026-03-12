import { useState, useCallback } from 'react';
import axios from 'axios';
import { sanitizeInput, validateURL, createRateLimiter } from '../utils/security';

const rateLimiter = createRateLimiter(10, 60000); // 10 requests per minute

export const useSecureAPI = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const secureRequest = useCallback(async (method, url, data = null) => {
    // Rate limiting
    if (!rateLimiter('api-calls')) {
      throw new Error('Too many requests. Please try again later.');
    }

    setLoading(true);
    setError(null);

    try {
      // Validate URL
      if (!validateURL(url)) {
        throw new Error('Invalid URL');
      }

      // Sanitize data if present
      if (data) {
        const sanitizedData = {};
        Object.keys(data).forEach(key => {
          if (typeof data[key] === 'string') {
            sanitizedData[key] = sanitizeInput(data[key]);
          } else {
            sanitizedData[key] = data[key];
          }
        });
        data = sanitizedData;
      }

      const config = {
        method,
        url,
        timeout: 10000, // 10 second timeout
        headers: {
          'Content-Type': 'application/json',
        }
      };

      if (data) {
        config.data = data;
      }

      const response = await axios(config);
      return response.data;
    } catch (err) {
      const errorMessage = err.response?.data?.message || err.message || 'An error occurred';
      setError(errorMessage);
      throw new Error(errorMessage);
    } finally {
      setLoading(false);
    }
  }, []);

  return { secureRequest, loading, error };
};
