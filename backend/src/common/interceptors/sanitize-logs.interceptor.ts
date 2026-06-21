import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

@Injectable()
export class SanitizeLogsInterceptor implements NestInterceptor {
  private sensitiveFields = [
    'password',
    'passwordHash',
    'token',
    'accessToken',
    'refreshToken',
    'invitationToken',
    'paymentDetails',
    'creditCard',
    'ssn',
    'bankAccount',
  ];

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      map((response) => {
        this.sanitizeObject(response);
        return response;
      }),
    );
  }

  private sanitizeObject(obj: any): void {
    if (!obj || typeof obj !== 'object') {
      return;
    }

    for (const key in obj) {
      if (obj.hasOwnProperty(key)) {
        if (this.sensitiveFields.some(field => key.toLowerCase().includes(field))) {
          obj[key] = '***REDACTED***';
        } else if (typeof obj[key] === 'object') {
          this.sanitizeObject(obj[key]);
        }
      }
    }
  }
}
